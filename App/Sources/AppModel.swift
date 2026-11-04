import Foundation
import SwiftUI
import Network
import UserNotifications
import RelayCore

enum ConnState: Equatable {
    case off, noNetwork, connecting, connected
    case error(String)

    var label: String {
        switch self {
        case .off: return "Nicht eingerichtet"
        case .noNetwork: return "Kein Netz"
        case .connecting: return "Verbinde…"
        case .connected: return "Verbunden"
        case .error(let m): return m
        }
    }
}

/// App state: one SSH link to the Desktop's `serve` channel, the session list, and the events that change it.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // settings
    @AppStorage("host") var host = ""
    @AppStorage("port") var port = 22
    @AppStorage("user") var user = ""
    @AppStorage("hostKey") var hostKey = ""
    @AppStorage("lastSeq") var lastSeq = 0
    @AppStorage("notify") var notifyEnabled = true
    @AppStorage("pinnedKeys") private var pinnedRaw = ""
    @AppStorage("unreadKeys") private var unreadRaw = ""
    @AppStorage("mutedKeys") private var mutedRaw = ""
    @AppStorage("lockEnabled") var lockEnabled = false

    @Published private(set) var state: ConnState = .off
    @Published private(set) var sessions: [String: Session] = [:]
    @Published private(set) var accounts: [Account] = []
    @Published var showDormant = false
    @Published var lastError: String?
    @Published var openChat: String?   // a session key to navigate to (notification tap)
    @Published var openJarvis = false  // Siri / Action Button shortcut
    @Published var locked = false      // Face ID lock shown

    /// Chats that watch a session receive its `transcript_append` here.
    var transcriptListeners: [String: (String, [TMessage]) -> Void] = [:]

    let identity: Identity
    private var link: GatewayLink?
    private var loop: Task<Void, Never>?
    private var kick = false
    private let monitor = NWPathMonitor()
    private var hasNetwork = true
    private var foreground = true
    var visibleChat: String?

    var pinned: Set<String> {
        get { Set(pinnedRaw.split(separator: "\n").map(String.init)) }
        set { pinnedRaw = newValue.sorted().joined(separator: "\n") }
    }
    var unread: Set<String> {
        get { Set(unreadRaw.split(separator: "\n").map(String.init)) }
        set { unreadRaw = newValue.sorted().joined(separator: "\n") }
    }
    /// Sessions whose "ready" / "waiting" notifications are silenced (they still show as unread).
    var muted: Set<String> {
        get { Set(mutedRaw.split(separator: "\n").map(String.init)) }
        set { mutedRaw = newValue.sorted().joined(separator: "\n"); objectWillChange.send() }
    }

    var configured: Bool { ServerConfig(host: host, port: port, user: user).isComplete }
    var publicKey: String { identity.openSSHPublicKey() }
    var setupCommand: String { "notifyd setup key \"\(publicKey)\"" }

    private init() {
        locked = UserDefaults.standard.bool(forKey: "lockEnabled")
        if let seed = Keychain.get("ssh-seed"), let id = try? Identity(rawSeed: seed) { identity = id }
        else { let id = Identity(); Keychain.set(id.rawSeed, for: "ssh-seed"); identity = id }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let had = self.hasNetwork
                self.hasNetwork = path.status == .satisfied
                if self.hasNetwork != had { self.reconnect() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "net"))
    }

    // MARK: connection loop

    func start() {
        guard loop == nil else { return }
        loop = Task { await runLoop() }
    }

    func reconnect() {
        kick = true
        link?.close()
    }

    func setForeground(_ fg: Bool) {
        foreground = fg
        if fg {
            if oneShot != nil { link?.close() } // a background check's link: the main loop takes over
            else if link?.isOpen != true { reconnect() }
        }
    }

    private func makeLink() -> GatewayLink {
        let cfg = ServerConfig(host: host.trimmingCharacters(in: .whitespaces), port: port, user: user.trimmingCharacters(in: .whitespaces))
        return GatewayLink(config: cfg, identity: identity, pinnedHostKey: hostKey.isEmpty ? nil : hostKey,
                           onHostKey: { key in Task { @MainActor in AppModel.shared.hostKey = key } },
                           onEvent: { ev in Task { @MainActor in AppModel.shared.handle(ev) } })
    }

    // MARK: short connections while in the background (notification actions, background refresh)

    private var oneShot: Task<Void, Never>?

    /// Makes sure a link is up, opening a one-off one when the app is in the background (the main loop sleeps there).
    /// Returns once `hello_ok` has been handled, or false after `timeout` seconds.
    func connectOnce(timeout: Double = 20) async -> Bool {
        if state == .connected, link?.isOpen == true { return true }
        guard configured else { return false }
        if foreground {
            reconnect()
        } else if oneShot == nil {
            link?.close()
            let l = makeLink()
            link = l
            state = .connecting
            let hello = Hello.make(sinceSeq: lastSeq, pinned: Array(pinned), appVersion: Self.appVersion)
            oneShot = Task { [weak self] in
                try? await l.run(hello: hello)
                guard let self else { return }
                if self.link === l { self.link = nil; if !self.foreground { self.state = .off } }
                self.oneShot = nil
            }
        }
        let until = Date().addingTimeInterval(timeout)
        while Date() < until && !Task.isCancelled {
            if state == .connected, link?.isOpen == true { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    /// Ends a background link again (the main loop reconnects when the app comes back).
    func releaseBackground() {
        if !foreground, oneShot != nil { link?.close() }
    }

    /// Background refresh: connect, let the replayed events raise their notifications, disconnect.
    func backgroundCheck() async -> Bool {
        guard await connectOnce(timeout: 20) else { releaseBackground(); return false }
        try? await Task.sleep(nanoseconds: 1_500_000_000) // late events after hello_ok
        releaseBackground()
        return true
    }

    func replyFromNotification(key: String, text: String) async {
        guard await connectOnce() else {
            notifyRaw(id: "reply-fail-\(key)", title: "Antwort nicht gesendet", body: "Keine Verbindung zum Desktop: \(text)", key: key)
            return
        }
        if let s = session(for: key) {
            do { try await send(s, text: text) ; markRead(s.key) }
            catch { notifyRaw(id: "reply-fail-\(key)", title: "Antwort nicht gesendet", body: "\(error.localizedDescription): \(text)", key: key) }
        }
        releaseBackground()
    }

    func doneFromNotification(key: String) async {
        if await connectOnce(), let s = session(for: key) { await done(s) }
        releaseBackground()
    }

    func toggleMute(_ key: String) {
        var m = muted
        if m.contains(key) { m.remove(key) } else { m.insert(key) }
        muted = m
    }

    private func runLoop() async {
        var backoff: Double = 2
        while !Task.isCancelled {
            guard configured else { state = .off; try? await Task.sleep(nanoseconds: 1_000_000_000); continue }
            guard hasNetwork else { state = .noNetwork; try? await Task.sleep(nanoseconds: 1_000_000_000); continue }
            if !foreground { // background: stay offline until we come back (background checks use connectOnce)
                while !foreground && !Task.isCancelled { try? await Task.sleep(nanoseconds: 500_000_000) }
            }
            while oneShot != nil { try? await Task.sleep(nanoseconds: 100_000_000) }
            state = .connecting
            kick = false
            let l = makeLink()
            link = l
            let started = Date()
            let hello = Hello.make(sinceSeq: lastSeq, pinned: Array(pinned), appVersion: Self.appVersion)
            do { try await l.run(hello: hello) }
            catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                if link === l { state = .error(msg) }
                if error is HostKeyMismatch { lastError = msg }
            }
            if link === l { link = nil }
            if Date().timeIntervalSince(started) > 20 { backoff = 2 }
            // wait: backoff, or until a kick / foreground comes back
            let until = Date().addingTimeInterval(kick ? 0.3 : backoff)
            while Date() < until && !kick { try? await Task.sleep(nanoseconds: 250_000_000) }
            if !foreground { // background: stay offline until we come back
                while !foreground && !Task.isCancelled { try? await Task.sleep(nanoseconds: 500_000_000) }
            }
            backoff = min(backoff * 2, 30)
        }
    }

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "ios \(v) (\(b))"
    }

    // MARK: rpc

    func rpc(_ method: String, _ params: JSON = [:], timeout: Double = 30, onProgress: (@Sendable (String) -> Void)? = nil) async throws -> JSON {
        if link?.isOpen != true {
            // wait briefly while connecting
            for _ in 0..<40 where state == .connecting { try await Task.sleep(nanoseconds: 250_000_000) }
        }
        guard let l = link, l.isOpen else { throw RelayError("Nicht verbunden: \(state.label)") }
        return try await l.rpc(method, params, timeout: timeout, onProgress: onProgress)
    }

    // MARK: events

    private func handle(_ ev: JSON) {
        let seq = ev["seq"].int ?? 0
        let replay = ev.flag("replay")
        defer { if seq > lastSeq { lastSeq = seq } }
        switch ev.str("type") {
        case "hello_ok":
            state = .connected
            var fresh: [String: Session] = [:]
            for s in ev["sessions"].array.compactMap(Session.from) { fresh[s.key] = s }
            // keep known dormant sessions the user may be looking at
            for (k, s) in sessions where fresh[k] == nil && (s.exited || s.closed) { fresh[k] = s }
            sessions = fresh
            accounts = ev["accounts"].array.compactMap(Account.from)
            if let s = ev["seq"].int, s > lastSeq { lastSeq = s }
            if pendingDigest > 0 { postDigest() }
        case "session_started":
            if let s = Session.from(ev["session"]) { replacePlaceholder(for: s); sessions[s.key] = s }
        case "session_state":
            guard let s = Session.from(ev["session"]) else { return }
            let prev = ev["prev_state"].string ?? sessions[s.key]?.state
            sessions[s.key] = s
            onStateChange(s, prev: prev, ev: ev, replay: replay)
        case "session_ended":
            let key = ev.str("session_key")
            if var s = Session.from(ev["session"]) ?? sessions[key] {
                if s.placeholder { sessions[key] = nil; return }
                s.state = "exited"
                sessions[s.key] = s
                if !ev.flag("by_user") && !replay { notify(s, title: "Beendet", body: s.lastMessage) }
            }
        case "session_done":
            let key = ev.str("session_key")
            sessions[key]?.asks = false
        case "session_seen":
            var u = unread; u.remove(ev.str("session_key")); unread = u
        case "transcript_append":
            let key = ev.str("session_key")
            let msgs = ev["messages"].array.map(TMessage.from)
            transcriptListeners.values.forEach { $0(key, msgs) }
        case "notice":
            if !replay { notifyRaw(id: "notice-\(seq)", title: ev.str("title", "Relay"), body: ev.str("text"), key: nil) }
        case "needs_confirmation":
            if !replay { notifyRaw(id: "confirm-\(ev.str("action_id"))", title: "Bestätigung nötig", body: ev.str("description"), key: nil) }
        default: break
        }
    }

    private func replacePlaceholder(for s: Session) {
        guard let t = s.tmuxSession else { return }
        for (k, old) in sessions where old.placeholder && old.tmuxSession == t { sessions[k] = nil }
    }

    private var pendingDigest = 0
    private var digestLines: [String] = []
    private var missed: [String: (title: String, body: String)] = [:]

    private func onStateChange(_ s: Session, prev: String?, ev: JSON, replay: Bool) {
        let now = s.state
        let ready = prev == "busy" && now == "idle"
        let needs = now == "needs_input" && prev != "needs_input"
        guard ready || needs else {
            if now == "busy", ev.str("origin") == "user" { clearNotifications(for: s.key) }
            return
        }
        if s.key != visibleChat || !foreground { var u = unread; u.insert(s.key); unread = u }
        if ev.flag("quiet") { return }
        let asks = ev.flag("asks")
        if ready && !asks && ev.str("origin") == "auto" && (ev["tasks"].int ?? 0) > 0 { return }
        if muted.contains(s.key) { return }
        let title = needs ? "Braucht Eingabe · \(s.name)" : (asks ? "Fragt dich · \(s.name)" : "Fertig · \(s.name)")
        let body = needs ? (ev["message"].string ?? s.question?.text ?? "Wartet auf deine Eingabe") : (asks ? s.asksText : s.lastMessage)
        if replay {
            pendingDigest += 1
            digestLines.append("\(s.name): \(needs || asks ? "wartet auf dich" : "fertig")")
            missed[s.key] = (title, body)
            return
        }
        if ev.flag("desk") && !needs { return }
        if s.key == visibleChat && foreground { return }
        notify(s, title: title, body: body)
    }

    private func postDigest() {
        let lines = digestLines
        let n = pendingDigest
        let each = missed
        pendingDigest = 0; digestLines = []; missed = [:]
        guard n > 0 else { return }
        if each.count <= 3 { // few: one notification per session, with reply actions
            for (key, m) in each where !(key == visibleChat && foreground) {
                notifyRaw(id: "s-\(key)", title: m.title, body: m.body, key: key)
            }
            return
        }
        notifyRaw(id: "digest", title: "Relay: \(n) Änderung\(n == 1 ? "" : "en")", body: lines.suffix(6).joined(separator: "\n"), key: nil)
    }

    // MARK: notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Actions on a session notification: answer inline, mark done, mute the session.
    static func registerNotificationActions() {
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Antworten", options: [],
                                                  textInputButtonTitle: "Senden", textInputPlaceholder: "Nachricht an die Sitzung")
        let done = UNNotificationAction(identifier: "done", title: "Erledigt", options: [])
        let mute = UNNotificationAction(identifier: "mute", title: "Stummschalten", options: [])
        let cat = UNNotificationCategory(identifier: "session", actions: [reply, done, mute], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    private func notify(_ s: Session, title: String, body: String) {
        notifyRaw(id: "s-\(s.key)", title: title, body: body, key: s.key)
    }

    private func notifyRaw(id: String, title: String, body: String, key: String?) {
        guard notifyEnabled else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = String(body.prefix(300))
        c.sound = .default
        if let key { c.userInfo = ["key": key]; c.threadIdentifier = key; c.categoryIdentifier = "session" }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    func clearNotifications(for key: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["s-\(key)"])
    }

    // MARK: actions

    func markRead(_ key: String) { var u = unread; u.remove(key); unread = u; clearNotifications(for: key) }

    func togglePin(_ key: String) {
        var p = pinned
        if p.contains(key) { p.remove(key) } else { p.insert(key) }
        pinned = p
        Task { _ = try? await rpc("set_pinned", ["keys": JSON(Array(p).sorted())]) }
    }

    func refresh() async {
        do {
            let r = try await rpc("list_sessions", ["include_dormant": .bool(showDormant), "limit": 100])
            var fresh: [String: Session] = [:]
            for s in r["sessions"].array.compactMap(Session.from) { fresh[s.key] = s }
            sessions = fresh
        } catch { lastError = error.localizedDescription }
    }

    func send(_ s: Session, text: String, force: Bool = false) async throws {
        var p: [String: JSON] = ["text": .string(text), "enter": true, "force": .bool(force)]
        if s.liveTmux != nil { p["target"] = .string(s.target) } else { p["key"] = .string(s.key) }
        _ = try await rpc("send", .object(p))
    }

    func sendKeys(_ s: Session, _ keys: [String], expectMenu: String? = nil) async throws {
        var p: [String: JSON] = ["keys": JSON(keys), "enter": false]
        if s.liveTmux != nil { p["target"] = .string(s.target) } else { p["key"] = .string(s.key) }
        if let m = expectMenu, !m.isEmpty { p["expect_menu"] = .string(m) }
        _ = try await rpc("send", .object(p))
    }

    func sendSteps(_ s: Session, _ steps: [JSON], expectMenu: String? = nil) async throws {
        var p: [String: JSON] = ["steps": .array(steps), "enter": false]
        if s.liveTmux != nil { p["target"] = .string(s.target) } else { p["key"] = .string(s.key) }
        if let m = expectMenu, !m.isEmpty { p["expect_menu"] = .string(m) }
        _ = try await rpc("send", .object(p))
    }

    func done(_ s: Session) async {
        sessions[s.key]?.asks = false
        markRead(s.key)
        _ = try? await rpc("session_done", ["key": .string(s.key)])
    }

    func close(_ s: Session) async {
        do { _ = try await rpc("close", ["key": .string(s.key), "stop": true]); await refresh() }
        catch { lastError = error.localizedDescription }
    }

    func reopen(_ s: Session) async throws -> String {
        let r = try await rpc("reopen", ["key": .string(s.key)], timeout: 40)
        return r.str("target")
    }

    func launch(alias: String, cwd: String, prompt: String?, name: String?) async throws -> String {
        var p: [String: JSON] = ["alias": .string(alias), "cwd": .string(cwd)]
        if let prompt, !prompt.isEmpty { p["prompt"] = .string(prompt) }
        if let name, !name.isEmpty { p["name"] = .string(name) }
        let r = try await rpc("launch", .object(p), timeout: 40)
        return r.str("tmux_session")
    }

    func forgetHostKey() { hostKey = ""; lastError = nil; reconnect() }

    /// Uploads a file (≤ 50 MB) to the Desktop; returns its path there.
    func upload(name: String, data: Data, progress: ((Double) -> Void)? = nil) async throws -> String {
        let begin = try await rpc("upload_begin", ["name": .string(name), "size": .number(Double(data.count))])
        let id = begin.str("upload_id")
        let chunk = 512 * 1024
        var seq = 0
        var off = 0
        while off < data.count {
            let end = min(off + chunk, data.count)
            _ = try await rpc("upload_chunk", ["upload_id": .string(id), "seq": .number(Double(seq)),
                                               "data_b64": .string(data[off..<end].base64EncodedString())], timeout: 60)
            off = end; seq += 1
            progress?(Double(off) / Double(max(data.count, 1)))
        }
        let r = try await rpc("upload_end", ["upload_id": .string(id)])
        return r.str("path")
    }

    // MARK: derived lists

    var visibleSessions: [Session] {
        sessions.values.filter { !$0.background && (showDormant || !($0.exited || $0.closed || $0.hibernated)) }
    }

    func session(for ref: String) -> Session? {
        sessions[ref] ?? sessions.values.first { $0.matches(ref) && !$0.placeholder } ?? sessions.values.first { $0.matches(ref) }
    }
}
