import SwiftUI
import RelayCore

/// Approvals the Desktop asks for (`send_request`, only `executor: "desktop"`) and Jarvis confirmations
/// (`needs_confirmation`). Nothing is decided without a tap; the answer waits in a small outbox if the Desktop is
/// unreachable. Kept in a JSON file, so a restart does not lose a pending request.
@MainActor
final class Approvals: ObservableObject {
    static let shared = Approvals()

    @Published private(set) var requests: [SendReq] = []
    @Published private(set) var confirms: [Confirm] = []
    @Published var showSheet = false
    @Published var note: String?

    private var handled: [String] = []
    private var answers: [JSON] = []          // [{method, params, ts}] not yet delivered
    private var replayConfirms: [String: Confirm] = [:]
    private var noteTask: Task<Void, Never>?

    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("approvals.json")
    }

    private init() {
        guard let u = Self.url, let d = try? Data(contentsOf: u), let j = JSON.parse(d) else { return }
        requests = j["requests"].array.compactMap { SendReq.from(event: $0) }
        confirms = j["confirms"].array.compactMap { c in
            let id = c.str("id"); return id.isEmpty ? nil : Confirm(id: id, description: c.str("description"), ts: c.num("ts"))
        }
        handled = j["handled"].array.compactMap(\.string)
        answers = j["answers"].array
    }

    private func save() {
        let j = JSON.object([
            "requests": .array(requests.map { $0.json() }),
            "confirms": .array(confirms.map { .object(["id": .string($0.id), "description": .string($0.description), "ts": .number($0.ts)]) }),
            "handled": .array(handled.suffix(200).map { .string($0) }),
            "answers": .array(answers),
        ])
        if let u = Self.url, let d = j.serialized().data(using: .utf8) { try? d.write(to: u, options: .atomic) }
    }

    private func markHandled(_ id: String) { if !handled.contains(id) { handled.append(id) } }

    // MARK: derived

    private var now: Double { Date().timeIntervalSince1970 }
    var live: [SendReq] { requests.filter { $0.expiresAt > now } }
    var groups: [[SendReq]] { SendRules.groups(live) }
    var count: Int { groups.count + confirms.count }

    var stripText: String {
        let g = groups
        let first = confirms.isEmpty ? g.first.map { SendRules.headline($0[0]) } : confirms.first?.description
        return SendRules.stripText(groups: g.count, confirms: confirms.count, first: first)
    }

    // MARK: events

    func onEvent(_ ev: JSON, replay: Bool) {
        switch ev.str("type") {
        case "send_request":
            guard let r = SendReq.from(event: ev, now: now) else { return }
            guard SendRules.accept(now: now, r, pending: Set(requests.map(\.id)), handled: Set(handled)) else { return }
            requests.append(r)
            save()
            Notifier.post(id: "send-\(r.id)", title: SendRules.title(r), body: SendRules.body(r), userInfo: ["request": r.id], category: "approval")
        case "send_resolved":
            let id = ev.str("request_id")
            markHandled(id)
            requests.removeAll { $0.id == id }
            save()
            Notifier.remove(["send-\(id)"])
        case "needs_confirmation":
            let c = Confirm(id: ev.str("action_id"), description: ev.str("description"), ts: ev.num("ts"))
            guard !c.id.isEmpty else { return }
            if replay { replayConfirms[c.id] = c } else { add(c) }
        case "confirmation_resolved":
            let id = ev.str("action_id")
            replayConfirms[id] = nil
            confirms.removeAll { $0.id == id }
            save()
            Notifier.remove(["confirm-\(id)"])
        default: break
        }
    }

    private func add(_ c: Confirm) {
        guard !confirms.contains(where: { $0.id == c.id }) else { return }
        confirms.append(c)
        save()
        Notifier.post(id: "confirm-\(c.id)", title: "Bestätigung nötig", body: c.description, userInfo: ["confirm": c.id], category: "approval")
    }

    /// After the replay (hello_ok): confirmations still open and younger than 30 minutes.
    func flushReplay() {
        let t = now
        for c in replayConfirms.values where ConfirmRules.fresh(ts: c.ts, now: t) { add(c) }
        replayConfirms = [:]
        sweepExpired()
    }

    func sweepExpired() {
        let dead = requests.filter { $0.expiresAt <= now }
        guard !dead.isEmpty else { return }
        requests.removeAll { $0.expiresAt <= now }
        save()
        Notifier.remove(dead.map { "send-\($0.id)" })
    }

    /// After a reconnect: drop requests the Desktop no longer waits for. Only a definite answer removes one.
    func reconcile() async {
        let model = AppModel.shared
        for r in requests {
            do {
                let st = try await model.rpc("phone_request_status", ["request_id": .string(r.id)], timeout: 10).str("status")
                if st != "pending" { drop(r.id) }
            } catch {
                if error.localizedDescription.contains("no such request") { drop(r.id) }
            }
        }
        await flushAnswers()
    }

    /// An action button on an approval notification (the background link is closed again afterwards).
    func fromNotification(request: String?, confirm id: String?, ok: Bool) async {
        let model = AppModel.shared
        _ = await model.connectOnce()
        if let request { await decide([request], ok: ok) }
        if let id { await self.confirm(id, ok: ok) }
        model.releaseBackground()
    }

    private func drop(_ id: String) {
        markHandled(id)
        requests.removeAll { $0.id == id }
        save()
        Notifier.remove(["send-\(id)"])
    }

    // MARK: decisions

    /// The user's tap. `ids`: the request(s) answered; for "Freigeben" only the newest of a group.
    func decide(_ ids: [String], ok: Bool) async {
        for id in ids {
            guard let r = requests.first(where: { $0.id == id }) else { continue }
            drop(id)
            guard r.expiresAt > now else { continue }
            var p: [String: JSON] = ["request_id": .string(id), "ok": .bool(ok)]
            if !ok { p["error"] = "denied" }
            await answer("send_result", .object(p))
        }
    }

    func confirm(_ id: String, ok: Bool) async {
        confirms.removeAll { $0.id == id }
        save()
        Notifier.remove(["confirm-\(id)"])
        let model = AppModel.shared
        do {
            let r = try await model.rpc("confirm", ["action_id": .string(id), "ok": .bool(ok)], timeout: 30)
            let res = r.str("result")
            if !res.isEmpty { show(res) }
        } catch { show("Nicht beantwortet: \(error.localizedDescription)") }
    }

    func show(_ s: String) {
        note = s
        noteTask?.cancel()
        noteTask = Task { try? await Task.sleep(nanoseconds: 6_000_000_000); if !Task.isCancelled { note = nil } }
    }

    private func answer(_ method: String, _ params: JSON) async {
        do { _ = try await AppModel.shared.rpc(method, params, timeout: 20) }
        catch {
            answers.append(.object(["method": .string(method), "params": params, "ts": .number(now)]))
            save()
        }
    }

    /// Sends answers that could not be delivered earlier (older than 24 h or rejected while connected: dropped).
    func flushAnswers() async {
        guard !answers.isEmpty else { return }
        let todo = answers
        answers = []
        var keep: [JSON] = []
        for a in todo {
            if now - a.num("ts") > 86_400 { continue }
            do { _ = try await AppModel.shared.rpc(a.str("method"), a["params"], timeout: 20) }
            catch { if AppModel.shared.isConnected { continue } else { keep.append(a) } }
        }
        answers = keep + answers
        save()
    }
}

/// Banners at the top of every view: the Desktop sleeps, approvals wait.
struct TopNotices: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var ap = Approvals.shared

    var body: some View {
        VStack(spacing: 4) {
            if let at = model.desktopSleepAt {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(.indigo)
                    Text("Desktop schläft seit \(at.formatted(date: .omitted, time: .shortened))").font(.footnote)
                    Spacer()
                    Button("Erneut") { model.reconnect() }.font(.footnote)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            if ap.count > 0 {
                Button { ap.showSheet = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.orange)
                        Text(ap.stripText).font(.footnote.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            if let n = ap.note {
                Text(n).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, (model.desktopSleepAt != nil || ap.count > 0 || ap.note != nil) ? 12 : 0)
        .padding(.vertical, (model.desktopSleepAt != nil || ap.count > 0 || ap.note != nil) ? 4 : 0)
    }
}

/// The exact text of each waiting request, with "Freigeben" and "Ablehnen".
struct ApprovalSheet: View {
    @ObservedObject private var ap = Approvals.shared
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                if ap.confirms.isEmpty && ap.groups.isEmpty {
                    Text("Nichts zu entscheiden.").foregroundStyle(.secondary)
                }
                ForEach(ap.confirms) { c in
                    Section("Bestätigung von Jarvis") {
                        Text(c.description).textSelection(.enabled)
                        HStack {
                            Button("Bestätigen") { run { await ap.confirm(c.id, ok: true) } }.buttonStyle(.borderedProminent)
                            Button("Ablehnen", role: .destructive) { run { await ap.confirm(c.id, ok: false) } }.buttonStyle(.bordered)
                        }.disabled(busy)
                    }
                }
                ForEach(ap.groups, id: \.first?.id) { g in
                    let r = g[0]
                    Section(SendRules.title(r)) {
                        Text(SendRules.body(r)).textSelection(.enabled)
                        if !r.requestedBy.isEmpty { Text("Angefragt von \(r.requestedBy)").font(.caption).foregroundStyle(.secondary) }
                        Text("Läuft ab \(Date(timeIntervalSince1970: r.expiresAt).formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        if g.count > 1 { Text("\(g.count) gleiche Anfragen. Freigeben beantwortet nur die neueste.").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("Freigeben") { run { await ap.decide([r.id], ok: true) } }.buttonStyle(.borderedProminent)
                            Button("Ablehnen", role: .destructive) { run { await ap.decide(g.map(\.id), ok: false) } }.buttonStyle(.bordered)
                        }.disabled(busy)
                    }
                }
                Section { Text("Das Schließen dieses Fensters entscheidet nichts. Die Anfrage bleibt, bis du antwortest, sie am PC beantwortet wird oder abläuft.")
                    .font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("Freigaben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .onChange(of: ap.count) { _, n in if n == 0 { dismiss() } }
    }

    private func run(_ body: @escaping @MainActor () async -> Void) {
        busy = true
        Task { await body(); busy = false }
    }
}
