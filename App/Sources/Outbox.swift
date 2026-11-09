import SwiftUI
import UserNotifications
import RelayCore

/// Messages on their way to the Desktop. A message is on disk at once (written whole and replaced, so a crash leaves the
/// old or the new list); one worker sends them in order as soon as the link is up. Only a refusal by the gateway ends
/// the attempts (the row then offers "Wiederholen" and "Bearbeiten"). The `client_id` makes a second send harmless when
/// the answer got lost. Text only: a card's answer belongs to what the screen shows now and goes out at once or not at all.
@MainActor
final class Outbox: ObservableObject {
    static let shared = Outbox()

    @Published private(set) var items: [OutItem] = []
    private var started = false

    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("outbox.json")
    }

    /// Started once at launch: what a killed app left on disk goes out now.
    func start() {
        guard !started else { return }
        started = true
        if let u = Self.url, let d = try? Data(contentsOf: u) { items = OutboxLogic.restored(OutboxLogic.decode(d)) + items }
        Task { await worker() }
    }

    func items(for key: String) -> [OutItem] { items.filter { $0.key == key } }

    /// Queues a message and returns at once.
    @discardableResult
    func add(id: String = UUID().uuidString, key: String, text: String, force: Bool = false, files: [String] = []) -> OutItem {
        if let old = items.first(where: { $0.id == id }) { return old }
        let i = OutItem(id: id, key: key, text: text, at: Date().timeIntervalSince1970, force: force, files: files)
        update { $0 + [i] }
        return i
    }

    /// A message the gateway refused because the session works: kept and shown as failed, with "Trotzdem senden".
    func addRefused(id: String, key: String, text: String, error: String) {
        let i = OutItem(id: id, key: key, text: text, at: Date().timeIntervalSince1970, state: .failed, error: error)
        update { list in list.filter { $0.id != id } + [i] }
    }

    /// A failed one goes again under a new `client_id` (the gateway answers a known id with its first, refusing answer).
    func retry(_ id: String, force: Bool? = nil, move: Bool? = nil) {
        update { $0.map { $0.id == id ? OutboxLogic.retried($0, force: force, newId: UUID().uuidString, move: move) : $0 } }
    }

    /// `keepFiles`: "Bearbeiten" takes the attachments back into the field, so they stay on disk.
    func remove(_ id: String, keepFiles: Bool = false) {
        if !keepFiles, let i = items.first(where: { $0.id == id }) { removeFiles(i) }
        update { $0.filter { $0.id != id } }
    }

    /// The transcript shows these texts now (or they are old): delivered rows go.
    func sweep(seen texts: [String]) {
        let now = Date().timeIntervalSince1970
        let kept = OutboxLogic.sweep(items, seen: texts, now: now)
        if kept.count != items.count { update { _ in kept } }
    }

    private func update(_ f: ([OutItem]) -> [OutItem]) {
        items = f(items)
        if let u = Self.url { try? OutboxLogic.encode(items).write(to: u, options: .atomic) }
    }

    private func set(_ id: String, _ f: (OutItem) -> OutItem) {
        update { $0.map { $0.id == id ? f($0) : $0 } }
    }

    private func worker() async {
        var waits = 0
        let model = AppModel.shared
        while !Task.isCancelled {
            guard let item = OutboxLogic.next(items) else { waits = 0; try? await Task.sleep(nanoseconds: 700_000_000); continue }
            if model.state != .connected || model.isForeground == false {
                if model.isForeground {
                    try? await Task.sleep(nanoseconds: 500_000_000) // the main loop reconnects by itself
                    continue
                }
                // in the background: a short link of its own, with extra time from iOS
                var ok = false
                await BackgroundRefresh.withBackgroundTime { ok = await model.connectOnce(timeout: 20) }
                if !ok {
                    let until = Date().addingTimeInterval(OutboxLogic.wait(waits))
                    waits += 1
                    while Date() < until && !model.isForeground && !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000_000) }
                    continue
                }
            }
            waits = 0
            set(item.id) { var c = $0; c.state = .sending; c.tries += 1; c.error = nil; return c }
            do {
                // the vault chat delivers every waiting message at once when it starts its agent
                for id in try await deliver(item) {
                    set(id) { var c = $0; c.state = .delivered; c.doneAt = Date().timeIntervalSince1970; c.error = nil; return c }
                }
            } catch {
                if OutboxLogic.retries(error) {
                    set(item.id) { var c = $0; c.state = .queued; c.error = error.localizedDescription; return c }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                } else {
                    let why = error.localizedDescription
                    set(item.id) { var c = $0; c.state = .failed; c.error = why; return c }
                    notifyFailed(item, why: why)
                }
            }
            if !model.isForeground && OutboxLogic.next(items) == nil { model.releaseBackground() }
        }
    }

    /// Sends one item; returns the ids now delivered (more than one when the vault chat starts its agent).
    private func deliver(_ item: OutItem) async throws -> [String] {
        if VaultChat.isVault(item.key) { return try await deliverVault(item) }
        let model = AppModel.shared
        if let s = model.session(for: item.key) {
            try await model.send(s, text: item.text, force: item.force, clientId: item.id, move: item.move)
        } else {
            _ = try await model.rpc("send", .obj(["key": .string(item.key), "text": .string(item.text), "enter": true,
                                                  "force": .bool(item.force), "client_id": .string(item.id),
                                                  "move": item.move ? .bool(true) : nil]), timeout: 60)
        }
        return [item.id]
    }

    // MARK: vault chat

    private static let vaultTargetKey = "vaultChatTarget", vaultLaunchedKey = "vaultChatLaunchedAt"

    /// The session the vault chat started last (`tmux:<name>` right after the launch).
    var vaultTarget: String? {
        get { UserDefaults.standard.string(forKey: Self.vaultTargetKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.vaultTargetKey); objectWillChange.send() }
    }

    /// Where attachments of the vault chat wait until they are uploaded.
    static var filesDir: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        let d = base.appendingPathComponent("vault-outbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Keeps an attachment on the phone; returns its stored name (nil when it could not be written).
    static func storeFile(name: String, data: Data) -> String? {
        let stored = VaultChat.storedName(id: UUID().uuidString, name: name)
        guard let d = filesDir else { return nil }
        do { try data.write(to: d.appendingPathComponent(stored), options: .atomic) } catch { return nil }
        return stored
    }

    static func dropFile(_ stored: String) {
        if let d = filesDir { try? FileManager.default.removeItem(at: d.appendingPathComponent(stored)) }
    }

    private func removeFiles(_ i: OutItem) { i.files.forEach(Self.dropFile) }

    /// The message with its attachments uploaded (their PC paths appended). An attachment gone from disk is skipped.
    private func uploadedBody(_ i: OutItem) async throws -> String {
        var paths: [String] = []
        for f in i.files {
            guard let d = Self.filesDir, let data = try? Data(contentsOf: d.appendingPathComponent(f)) else { continue }
            let (name, prepared) = await Task.detached(priority: .userInitiated) { AttachPrep.prepared(name: VaultChat.displayName(f), data: data) }.value
            paths.append(try await AppModel.shared.upload(name: name, data: prepared))
        }
        return VaultChat.body(i.text, paths: paths)
    }

    /// Vault chat: into the agent it started, while that one runs; otherwise a new agent in the vault folder gets every
    /// waiting message as its first prompt. A launch whose answer got lost is found by its name, never started twice.
    private func deliverVault(_ item: OutItem) async throws -> [String] {
        let model = AppModel.shared
        if let t = vaultTarget {
            // just started: the session shows up in the list a moment after the launch
            let launchedAt = UserDefaults.standard.double(forKey: Self.vaultLaunchedKey)
            var s = model.session(for: t)
            var n = 0
            while s == nil && Date().timeIntervalSince1970 - launchedAt < 120 && n < 15 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await model.refresh()
                s = model.session(for: t); n += 1
            }
            if let s, VaultChat.reusable(alive: s.alive, closed: s.closed, hibernated: s.hibernated) {
                let body = VaultChat.followUp(try await uploadedBody(item), at: item.at)
                try await model.send(s, text: body, force: true, clientId: item.id)
                removeFiles(item)
                return [item.id]
            }
        }
        let batch = VaultChat.batch(items, next: item)
        let tag = VaultChat.tag(item.id)
        if item.tries > 1 {
            await model.refresh()
            if let key = VaultChat.launched(model.sessions.values.map { (key: $0.key, name: $0.name) }, tag: tag) {
                vaultTarget = key
                batch.forEach(removeFiles)
                return batch.map(\.id)
            }
        }
        var messages: [(at: Double, text: String)] = []
        for i in batch { messages.append((at: i.at, text: try await uploadedBody(i))) }
        let tmux = try await model.launch(alias: model.defaultLaunchAlias, cwd: model.vaultDir,
                                          prompt: VaultChat.prompt(messages), name: VaultChat.sessionName(tag: tag))
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.vaultLaunchedKey)
        vaultTarget = "tmux:\(tmux)"
        batch.forEach(removeFiles)
        UsageRecorder.shared.record("vault-chat", "agent gestartet", kind: "text", length: batch.count)
        return batch.map(\.id)
    }

    /// The chat may be closed by now: this one has to reach the user.
    private func notifyFailed(_ item: OutItem, why: String) {
        let model = AppModel.shared
        if model.isForeground && model.visibleChat == item.key { return }
        let c = UNMutableNotificationContent()
        c.title = "Nachricht nicht gesendet"
        c.body = String("\(why): \(item.text)".prefix(300))
        c.sound = .default
        c.userInfo = ["key": item.key]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "outbox-\(item.id)", content: c, trigger: nil))
    }
}

/// An outbox item in the chat: a grey bubble with its state; a failed one offers retry and edit.
struct OutboxRow: View {
    @EnvironmentObject var model: AppModel
    let item: OutItem
    let onEdit: (String) -> Void
    /// „Am PC beenden und hier fortsetzen…“: der Chat fragt erst nach (DeskTerminal), dann `retry(move: true)`.
    var onMove: (String) -> Void = { _ in }

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.text).padding(10)
                    .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(item.state == .delivered ? .primary : .secondary)
                HStack(spacing: 8) {
                    if item.state == .sending || (item.state == .queued && model.state == .connected) { ProgressView().controlSize(.mini) }
                    Text(OutboxLogic.status(item, connected: model.state == .connected, network: model.state != .noNetwork))
                        .font(.caption2).foregroundStyle(item.state == .failed ? Color.red : Color.secondary)
                }
                if item.state == .failed {
                    HStack(spacing: 8) {
                        // stuck in the PC's input field: a retry would type it twice there
                        if !SubmitCheck.isStuck(item.error ?? "") { Button("Wiederholen") { Outbox.shared.retry(item.id) } }
                        if OutboxLogic.isBusyRefusal(item.error ?? "") { Button("Trotzdem senden") { Outbox.shared.retry(item.id, force: true) } }
                        if DeskTerminal.isRefusal(item.error ?? "") { Button(DeskTerminal.moveButton) { onMove(item.id) } }
                        Button("Bearbeiten") { onEdit(item.text); Outbox.shared.remove(item.id) }
                        Button("Verwerfen", role: .destructive) { UsageRecorder.shared.record("chat", "postausgang verworfen", session: item.key, kind: "text", length: item.text.count); Outbox.shared.remove(item.id) }
                    }.font(.caption).buttonStyle(.bordered).controlSize(.mini)
                } else if item.state == .queued {
                    Button("Bearbeiten") { onEdit(item.text); Outbox.shared.remove(item.id) }
                        .font(.caption).buttonStyle(.bordered).controlSize(.mini)
                }
            }
        }
        .padding(.horizontal)
    }
}
