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
    @AppStorage("host2") var host2 = ""          // second address of the same PC (VPN); the reachable one is used
    @AppStorage("lastGoodHost") var lastGoodHost = ""
    @AppStorage("port") var port = 22
    @AppStorage("user") var user = ""
    @AppStorage("hostKey") var hostKey = ""
    @AppStorage("lastSeq") var lastSeq = 0
    @AppStorage("notify") var notifyEnabled = true
    @AppStorage("pinnedKeys") private var pinnedRaw = ""
    @AppStorage("unreadKeys") private var unreadRaw = ""
    @AppStorage("mutedKeys") private var mutedRaw = ""
    @AppStorage("lockEnabled") var lockEnabled = false
    @AppStorage("lastSync") var lastSync: Double = 0
    @AppStorage("avatarLook") private var avatarLookRaw = ""
    @AppStorage("lastOpenedKey") var lastOpenedKey = ""
    @AppStorage("favDirs") private var favDirsRaw = ""
    @AppStorage("lastAlias") var lastAlias = ""
    @AppStorage("vaultDir") var vaultDir = VaultDrop.defaultDir   // "Ins Vault einsortieren": the vault folder on the PC

    @Published private(set) var state: ConnState = .off {
        didSet {
            guard state != oldValue else { return }
            if case .error(let m) = state { UsageRecorder.shared.record("app", "verbindung", detail: "Fehler", error: m) }
            else { UsageRecorder.shared.record("app", "verbindung", detail: state.label) }
            if state == .connected { Task { await UsageRecorder.shared.flush() } }
            tailnetUp = TailscaleLauncher.tailnetUp()
            // der Grund des letzten Fehlversuchs bleibt beim nächsten „Verbinde…“ stehen, sonst flackert die Hilfe
            if state == .connected || state == .off { problem = nil; problemMessage = "" }
            if state == .noNetwork { problem = .noNetwork; problemMessage = "" }
            else if oldValue == .noNetwork, problem == .noNetwork { problem = nil }
        }
    }
    /// Why the last connect attempt failed (`ConnectDiagnosis`); nil while connected or before the first failure.
    @Published private(set) var problem: ConnectProblem? {
        didSet {
            guard problem != oldValue, let p = problem else { return }
            UsageRecorder.shared.record("app", "verbindungsgrund", detail: p.rawValue)
        }
    }
    private var problemMessage = ""
    /// The link of the current attempt got its `hello_ok` (a later failure is a cut link, not a gateway that is down).
    private var linkGotHello = false
    /// The phone is in a Wi-Fi (a home-network address of the PC may be reachable).
    private var onWifi = true
    /// Title, explanation and buttons for the failed link (row above the session list); nil when there is nothing to say.
    var connectHelp: ConnectHelp? {
        guard state != .connected, let p = problem else { return nil }
        return ConnectDiagnosis.help(p, message: problemMessage, hosts: hosts, tailnetUp: tailnetUp)
    }
    /// A tailnet address (Tailscale on) is on the phone.
    @Published private(set) var tailnetUp = false
    @Published private(set) var sessions: [String: Session] = [:]
    /// „Alle Sitzungen beenden“ (WindDown): der laufende Auftrag des Gateways und sein Stand.
    @Published private(set) var windDownJob: String?
    @Published private(set) var windDownItems: [WindDown.Item] = []
    @Published private(set) var windDownDone = false
    @Published private(set) var accounts: [Account] = []
    @Published var showDormant = false      // "Zuletzt" instead of "Laufend"
    @Published var showBackground = false   // also headless runs
    @Published private(set) var hidden: Set<String> = []   // closed with Undo pending
    @Published private(set) var undoable: Session?
    @Published private(set) var memory: MemoryInfo?
    @Published private(set) var usage: [UsageAccount] = []
    @Published private(set) var cloudSessions: [CloudSession] = []
    @Published private(set) var cloudError = ""
    @Published private(set) var cloudChecked: Double = 0
    @Published private(set) var look = Avatars.Look()
    @Published var lastError: String? { didSet { if let e = lastError, e != oldValue { AppLog.shared.log("warn", "ui", e); UsageRecorder.shared.record("app", "fehler", error: e) } } }
    @Published private(set) var vpnActive = false
    @Published private(set) var activeHost = ""   // the address the current link uses (with two configured)
    @Published var openChat: String?   // a session key to navigate to (notification tap)
    @Published var openJarvis = false  // Siri / Action Button shortcut
    @Published var openDrive = false   // Kurzbefehl „Sprachmodus in Relay“
    @Published var voiceLive = false   // hello_ok.config.voice == "live": the Desktop offers Jarvis Live (not used here)
    var conversationActive = false     // Jarvis conversation mode is running (set by JarvisView)
    var driveActive = false            // Sprachmodus offen: er liest selbst vor, keine zweite Stimme (DriveView)
    var lastJarvisWarm = Date.distantPast
    var jarvisWarmUnsupported = false
    @Published var locked = false      // Face ID lock shown
    @Published var incomingFiles: [URL] = []  // "In Relay öffnen": files waiting for a target session
    @Published var openNotice: String? // a notice ref to open (notification tap)
    @Published private(set) var desktopSleepAt: Date?  // `desktop_sleep`: the PC suspends, retry every 5 min

    /// Chats that watch a session receive its `transcript_append` here.
    var transcriptListeners: [String: (String, [TMessage]) -> Void] = [:]

    let identity: Identity
    private var link: GatewayLink?
    private var loop: Task<Void, Never>?
    private var kick = false
    private let monitor = NWPathMonitor()
    private var hasNetwork = true
    var foreground = true
    var visibleChat: String?
    /// When the link last carried anything (event or answer): `ensureAlive` pings when it was quiet for a while.
    var lastTraffic = Date()
    var isForeground: Bool { foreground }
    var isConnected: Bool { state == .connected && link?.isOpen == true }

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

    var favDirs: [String] {
        get { FavDirs.decode(favDirsRaw) }
        set { favDirsRaw = FavDirs.encode(newValue); objectWillChange.send() }
    }

    /// A file opened in Relay from another app (document type): queued until the user picked a session.
    func receive(_ url: URL) {
        if let cb = Tailnet.callback(url) { tailscaleReturned(cb); return }
        guard url.isFileURL else { return }
        if !incomingFiles.contains(url) { incomingFiles.append(url) }
    }

    /// Back from the shortcut "Tailscale verbinden": connect again at once (or say why the shortcut failed).
    func tailscaleReturned(_ cb: Tailnet.Callback) {
        switch cb {
        case .connected:
            UsageRecorder.shared.record("app", "tailscale zurück", detail: "verbunden")
            tailnetUp = TailscaleLauncher.tailnetUp()
            reconnect()
        case .failed(let msg):
            UsageRecorder.shared.record("app", "tailscale zurück", detail: "Fehler", error: msg)
            lastError = Tailnet.failureText(shortcut: TailscaleLauncher.shortcutName, message: msg)
        }
    }

    /// Forget the queued files and delete the copies iOS put into our Inbox.
    func dropIncoming() {
        for u in incomingFiles where u.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: u) }
        incomingFiles = []
    }

    func rememberOpened(_ key: String) { if !key.isEmpty { lastOpenedKey = key } }

    /// The state in words; after a failed attempt the reason in plain words instead of the raw error.
    var connLabel: String {
        switch state {
        case .noNetwork, .error: return connectHelp?.title ?? state.label
        default: return state.label
        }
    }

    /// The PC's addresses (primary, optional second one), cleaned.
    var hosts: [String] { HostChoice.candidates([host, host2]) }

    /// The address for the next connect: with two of them, a 3 s TCP probe of both (the one that worked last time is
    /// tried first in the fallback), the first to answer wins; nobody answering keeps the usual order.
    private func chooseHost() async -> String {
        let c = hosts
        guard c.count > 1 else { return c.first ?? host.trimmingCharacters(in: .whitespaces) }
        let ordered = HostChoice.order(candidates: c, lastGood: lastGoodHost)
        let hit = await Reach.first(of: ordered, port: port, timeout: 3)
        return HostChoice.pick(candidates: c, reachable: hit.map { [$0] } ?? [], lastGood: lastGoodHost) ?? ordered[0]
    }

    var configured: Bool { ServerConfig(host: host, port: port, user: user).isComplete }
    var publicKey: String { identity.openSSHPublicKey() }
    var setupCommand: String { "notifyd setup key \"\(publicKey)\"" }

    private init() {
        UITestMode.prepare()
        locked = UserDefaults.standard.bool(forKey: "lockEnabled")
        if let seed = UITestMode.seed, let id = try? Identity(rawSeed: seed) { identity = id }
        else if let seed = Keychain.get("ssh-seed"), UITestMode.active == false, let id = try? Identity(rawSeed: seed) { identity = id }
        else { let id = Identity(); Keychain.set(id.rawSeed, for: "ssh-seed"); identity = id }
        if let raw = JSON.parse(avatarLookRaw) { look = Avatars.look(from: raw) }
        if let cached = Self.loadSessionCache() {
            for s in cached.array.compactMap(Session.from) { sessions[s.key] = s }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.vpnActive = path.usesInterfaceType(.other)
                self.onWifi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                let had = self.hasNetwork
                self.hasNetwork = path.status == .satisfied
                let tailnetHad = self.tailnetUp
                self.tailnetUp = TailscaleLauncher.tailnetUp()
                if self.hasNetwork != had { self.reconnect() }
                // Tailscale ist (wieder) an: sofort neu versuchen statt auf das nächste Intervall zu warten
                else if self.tailnetUp && !tailnetHad && self.state != .connected { self.reconnect() }
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
            PhoneAccessStore.shared.foregroundCame()
            if oneShot != nil { link?.close() } // a background check's link: the main loop takes over
            else if link?.isOpen != true && state != .connecting { reconnect() }
        }
    }

    private func makeLink(host: String) -> GatewayLink {
        activeHost = host
        let cfg = ServerConfig(host: host, port: port, user: user.trimmingCharacters(in: .whitespaces))
        // Ereignisse einer schon ersetzten oder geschlossenen Verbindung dürfen den Zustand nicht mehr ändern
        // (sonst steht "Verbunden" bei toter Verbindung und jeder Aufruf scheitert mit "Nicht verbunden").
        let box = LinkBox()
        let l = GatewayLink(config: cfg, identity: identity, pinnedHostKey: hostKey.isEmpty ? nil : hostKey,
                            onHostKey: { key in Task { @MainActor in AppModel.shared.hostKey = key } },
                            onEvent: { ev in Task { @MainActor in
                                let m = AppModel.shared
                                if let mine = box.link, m.link === mine { m.handle(ev) }
                            } })
        box.link = l
        return l
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
            state = .connecting
            // the task is set before the first await, so a second caller sees it and only waits below
            oneShot = Task { [weak self] in
                guard let self else { return }
                let l = self.makeLink(host: await self.chooseHost())
                self.link = l
                let hello = Hello.make(sinceSeq: self.lastSeq, pinned: Array(self.pinned), appVersion: Self.appVersion)
                try? await l.run(hello: hello)
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
        await PhoneAccessStore.shared.waitIdle(max: 20)    // Telefonzugriff: laufende Lesebefehle zu Ende bringen
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
            let l = makeLink(host: await chooseHost())
            link = l
            let started = Date()
            let hello = Hello.make(sinceSeq: lastSeq, pinned: Array(pinned), appVersion: Self.appVersion)
            linkGotHello = false
            do { try await l.run(hello: hello) }
            catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                if link === l {
                    if kick {
                        // selbst getrennt („Erneut“, zurück im Vordergrund, Netzwechsel): kein Fehler, gleich neu verbinden
                        state = .connecting
                    } else {
                        let facts = ConnectDiagnosis.Facts(
                            message: msg, stage: (error as? RelayError)?.stage, hostKeyChanged: error is HostKeyMismatch,
                            wasConnected: linkGotHello, network: hasNetwork, wifi: onWifi, vpn: vpnActive, hosts: hosts,
                            tailnetUp: TailscaleLauncher.tailnetUp(), pcSleeping: desktopSleepAt != nil)
                        problemMessage = msg
                        problem = ConnectDiagnosis.problem(facts)
                        state = .error(msg)
                    }
                }
                if error is HostKeyMismatch { lastError = msg }
            }
            if link === l { link = nil }
            if Date().timeIntervalSince(started) > 20 { backoff = 2 }
            // wait: backoff, or until a kick / foreground comes back
            // after `desktop_sleep` the PC is gone for a while: try every 5 minutes instead of hammering
            let until = Date().addingTimeInterval(kick ? 0.3 : (desktopSleepAt != nil ? 300 : backoff))
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
        guard let l = link, l.isOpen else { throw RelayError("Nicht verbunden: \(connLabel)") }
        let r = try await l.rpc(method, params, timeout: timeout, onProgress: onProgress)
        lastTraffic = Date()
        return r
    }

    // MARK: events

    private func handle(_ ev: JSON) {
        lastTraffic = Date()
        let seq = ev["seq"].int ?? 0
        let replay = ev.flag("replay")
        defer { if seq > lastSeq { lastSeq = seq }; if seq > 0 || ev.str("type") == "hello_ok" { lastSync = Date().timeIntervalSince1970 } }
        switch ev.str("type") {
        case "hello_ok":
            linkGotHello = true
            state = .connected
            if lastGoodHost != activeHost { lastGoodHost = activeHost }
            var fresh: [String: Session] = [:]
            for s in ev["sessions"].array.compactMap(Session.from) { fresh[s.key] = s }
            saveSessionCache(ev["sessions"])
            applyConfig(ev["config"])
            // sessions seen elsewhere after their last activity count as read
            var u = unread
            for s in fresh.values where Triage.seenAfterActivity(s) { u.remove(s.key) }
            if u != unread { unread = u }
            // keep known dormant sessions the user may be looking at
            for (k, s) in sessions where fresh[k] == nil && (s.exited || s.closed) { fresh[k] = s }
            sessions = fresh
            accounts = ev["accounts"].array.compactMap(Account.from)
            if let s = ev["seq"].int, s > lastSeq { lastSeq = s }
            desktopSleepAt = nil
            if !missed.isEmpty { postDigest() }
            Approvals.shared.flushReplay()
            AppLog.shared.flushSaved()
            Task { await Approvals.shared.reconcile() }
            Task { await PhoneAccessStore.shared.reconcile() }  // Telefonzugriff: Schalter melden, offene Befehle holen
        case "session_started":
            if let s = Session.from(ev["session"]) { replacePlaceholder(for: s); sessions[s.key] = s.keepingPC(from: sessions[s.key]) }
        case "session_state":
            guard let fresh = Session.from(ev["session"]) else { return }
            let s = fresh.keepingPC(from: sessions[fresh.key])  // Monitor-Ereignisse tragen kein pc_attached
            let prev = ev["prev_state"].string ?? sessions[s.key]?.state
            sessions[s.key] = s
            onStateChange(s, prev: prev, ev: ev, replay: replay)
        case "session_ended":
            let key = ev.str("session_key")
            let wasAlive = sessions[key].map { $0.state != "exited" } ?? true
            if var s = Session.from(ev["session"]) ?? sessions[key] {
                if s.placeholder { sessions[key] = nil; return }
                s.state = "exited"
                sessions[s.key] = s
                if !ev.flag("by_user") && wasAlive { onEnded(s, replay: replay, ts: ev.num("ts")) }
                else if replay { missed[s.key] = nil; missedOrder.removeAll { $0 == s.key } }
            }
        case "session_done":
            let key = ev.str("session_key")
            sessions[key]?.asks = false
        case "pc_attached":  // ein Terminal am PC hat die Sitzung geöffnet oder geschlossen: Anzeige „am PC offen“ (2026-11-07)
            PCPresence.apply(ev, to: &sessions)
        case "wind_down":
            if ev.str("job") == windDownJob { windDownItems = WindDown.apply(ev, to: windDownItems) }
        case "wind_down_done":
            if ev.str("job") == windDownJob {
                windDownDone = true
                UsageRecorder.shared.record("alle beenden", "fertig", detail: ev.str("summary").components(separatedBy: "\n").first)
                Task { await refreshWindDown(); await refresh() }
            }
        case "session_seen":
            let key = ev.str("session_key")
            var u = unread; u.remove(key); unread = u
            // "ready" and "ended" notifications go; a question stays while the session waits
            if let s = session(for: key), s.waits { break }
            clearNotifications(for: key)
            dropMissed(key)
        case "cloud_sessions":
            cloudSessions = ev["sessions"].array.compactMap(CloudSession.from)
            cloudChecked = ev.num("checked_at"); cloudError = ev.str("error")
        case "transcript_append":
            let key = ev.str("session_key")
            let msgs = ev["messages"].array.map(TMessage.from)
            transcriptListeners.values.forEach { $0(key, msgs) }
        case "notice":
            let now = Date().timeIntervalSince1970
            let n = Notice.from(event: ev, now: now)
            NoticeStore.shared.add(n)
            let answered = NoticeStore.shared.get(n.ref)?.answer != nil  // a replayed question already answered
            if NoticeLogic.show(ts: ev.num("ts"), now: now), !answered {
                // an agent's question: the notification carries the question and an "Antworten" field
                let q = Rueckfrage.question(n)
                Notifier.post(id: NoticeLogic.slot(tag: n.tag, seq: seq), title: n.title.isEmpty ? (q.map(Rueckfrage.title) ?? "Relay") : n.title,
                              body: q?.question ?? n.text, userInfo: ["notice": n.ref], category: q.flatMap(Rueckfrage.category))
            }
        case "send_request", "send_resolved", "needs_confirmation", "confirmation_resolved":
            Approvals.shared.onEvent(ev, replay: replay)
        case "location_request":
            Locator.shared.onRequest(ev, replay: replay)
        case "phone_command", "phone_command_resolved":
            PhoneAccessStore.shared.onEvent(ev, replay: replay)
        case "desktop_sleep":
            desktopSleepAt = Date(timeIntervalSince1970: ev.num("at", Date().timeIntervalSince1970))
        case "routine_run":
            RoutinesStore.shared.onRunEvent(ev)
        default: break
        }
    }

    private func replacePlaceholder(for s: Session) {
        guard let t = s.tmuxSession else { return }
        for (k, old) in sessions where old.placeholder && old.tmuxSession == t { sessions[k] = nil }
    }

    /// Replayed events that would have raised a notification, one per session (the last wins).
    private struct Missed { var title: String, body: String, line: String, alert: NotifyAlert }
    private var missed: [String: Missed] = [:]
    private var missedOrder: [String] = []

    private func addMissed(_ key: String, _ m: Missed) {
        if missed[key] == nil { missedOrder.append(key) }
        missed[key] = m
    }

    private func dropMissed(_ key: String) {
        missed[key] = nil
        missedOrder.removeAll { $0 == key }
    }

    private func alert(_ kind: AlertKind, key: String, ev: StateInfo? = nil) -> NotifyAlert {
        NotifyPolicy.alert(kind, NotifyDefaults.prefs(), muted: muted.contains(key), ev: ev,
                           minuteOfDay: QuietHours.minuteOfDay(Date()))
    }

    private func onStateChange(_ s: Session, prev: String?, ev: JSON, replay: Bool) {
        let now = s.state
        let ready = prev == "busy" && now == "idle"
        let needs = now == "needs_input" && prev != "needs_input"
        guard ready || needs else {
            if now == "busy", NotifyPolicy.clearsOnBusy(origin: ev.str("origin")) { clearNotifications(for: s.key); dropMissed(s.key) }
            return
        }
        if s.key != visibleChat || !foreground { var u = unread; u.insert(s.key); unread = u }
        // replayed events older than 24 h are not announced
        if replay, !NoticeLogic.show(ts: ev.num("ts"), now: Date().timeIntervalSince1970) { return }
        let info = StateInfo.from(ev)
        let asks = info.asks
        let al = alert(needs ? .needsInput : .ready, key: s.key, ev: info)
        if al == .none { if replay { dropMissed(s.key) }; return }
        let title = needs ? "Braucht Eingabe · \(s.name)" : (asks ? "Fragt dich · \(s.name)" : "Fertig · \(s.name)")
        let body = needs ? (ev["message"].string ?? s.question?.text ?? "Wartet auf deine Eingabe") : (asks ? s.asksText : s.lastMessage)
        if replay {
            addMissed(s.key, Missed(title: title, body: body, line: "\(s.name): \(needs || asks ? "wartet auf dich" : "fertig")", alert: al))
            return
        }
        if ready && !asks { announceFinished(s) }
        if s.key == visibleChat && foreground { return }
        notify(s, title: title, body: body, ready: ready && !asks, silent: al == .silent)
    }

    private func onEnded(_ s: Session, replay: Bool, ts: Double) {
        if replay, !NoticeLogic.show(ts: ts, now: Date().timeIntervalSince1970) { return }
        let al = alert(.ended, key: s.key)
        if al == .none { if replay { dropMissed(s.key) }; return }
        let title = "Beendet · \(s.name)"
        if replay { addMissed(s.key, Missed(title: title, body: s.lastMessage, line: "\(s.name): beendet", alert: al)); return }
        if s.key == visibleChat && foreground { return }
        notify(s, title: title, body: s.lastMessage, silent: al == .silent)
    }

    private func postDigest() {
        let each = missedOrder.compactMap { k in missed[k].map { (k, $0) } }
        missed = [:]; missedOrder = []
        guard !each.isEmpty else { return }
        if each.count <= 3 { // few: one notification per session, with reply actions
            for (key, m) in each where !(key == visibleChat && foreground) {
                notifyRaw(id: "s-\(key)", title: m.title, body: m.body, key: key, silent: m.alert == .silent)
            }
            return
        }
        let n = each.count
        let rings = each.contains { $0.1.alert == .popup }
        notifyRaw(id: "digest", title: "Relay: \(n) Änderung\(n == 1 ? "" : "en")", body: each.suffix(6).map { $0.1.line }.joined(separator: "\n"),
                  key: nil, silent: !rings)
    }

    // MARK: notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Actions on a session notification: answer inline, mark done, mute the session; approvals: allow / deny.
    /// With "Aktionen brauchen entsperrtes Gerät" the actions with input need an unlocked phone.
    static func registerNotificationActions() {
        let auth: UNNotificationActionOptions = NotifyDefaults.actionAuth ? [.authenticationRequired] : []
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Antworten", options: auth,
                                                  textInputButtonTitle: "Senden", textInputPlaceholder: "Nachricht an die Sitzung")
        let done = UNNotificationAction(identifier: "done", title: "Erledigt", options: [])
        let mute = UNNotificationAction(identifier: "mute", title: "Stummschalten", options: [])
        let cat = UNNotificationCategory(identifier: "session", actions: [reply, done, mute], intentIdentifiers: [], options: [])
        // "ready" notifications also carry the first quick reply ("Weiter") as a one-tap action
        var readyActions: [UNNotificationAction] = [reply]
        if let q = ChatPrefs.quickReplies.first { readyActions.append(UNNotificationAction(identifier: "quick", title: q, options: auth)) }
        readyActions += [done, mute]
        let ready = UNNotificationCategory(identifier: "session-ready", actions: readyActions, intentIdentifiers: [], options: [])
        // an approval is never given from a locked phone
        let approve = UNNotificationAction(identifier: "approve", title: "Freigeben", options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: "deny", title: "Ablehnen", options: [.destructive])
        let approval = UNNotificationCategory(identifier: "approval", actions: [approve, deny], intentIdentifiers: [], options: [])
        // an agent's question (rueckfrage): answer in the notification; "Ja" takes the agent's recommendation
        let answer = UNTextInputNotificationAction(identifier: "answer", title: "Antworten", options: auth,
                                                   textInputButtonTitle: "Senden", textInputPlaceholder: "Antwort an den Agenten")
        let yes = UNNotificationAction(identifier: "yes", title: "Ja (Empfehlung)", options: auth)
        let question = UNNotificationCategory(identifier: "rueckfrage", actions: [answer], intentIdentifiers: [], options: [])
        let questionYes = UNNotificationCategory(identifier: "rueckfrage-ja", actions: [yes, answer], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat, ready, approval, question, questionYes])
    }

    private func notify(_ s: Session, title: String, body: String, ready: Bool = false, silent: Bool = false) {
        notifyRaw(id: "s-\(s.key)", title: title, body: body, key: s.key, category: ready ? "session-ready" : "session", silent: silent)
    }

    private func notifyRaw(id: String, title: String, body: String, key: String?, category: String = "session", silent: Bool = false) {
        Notifier.post(id: id, title: title, body: body, userInfo: key.map { ["key": $0] } ?? [:], category: key == nil ? nil : category,
                      thread: key, silent: silent)
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
            var p: [String: JSON] = ["include_dormant": .bool(showDormant), "limit": 100]
            if showBackground { p["include_background"] = true }
            let r = try await rpc("list_sessions", .object(p))
            var fresh: [String: Session] = [:]
            for s in r["sessions"].array.compactMap(Session.from) { fresh[s.key] = s }
            sessions = fresh
            lastSync = Date().timeIntervalSince1970
            if !showDormant && !showBackground { saveSessionCache(r["sessions"]) }
        } catch { lastError = error.localizedDescription }
    }

    // MARK: triage data

    /// Sessions the "Weiter" queue and the strip count (no closing ones, no headless runs).
    var triageSessions: [Session] {
        sessions.values.filter { !hidden.contains($0.key) && !$0.background && !$0.placeholder }
    }

    func loadMemory() async {
        if let r = try? await rpc("memory", ["summary": true]) { memory = MemoryInfo.from(r) }
    }

    /// rpc `cloud_sessions` (gateway caches 60 s). Errors stay as text in `cloudError`, never thrown.
    func loadCloud(refresh: Bool = false) async {
        do {
            let r = try await rpc("cloud_sessions", ["refresh": .bool(refresh)], timeout: 40)
            cloudSessions = r["sessions"].array.compactMap(CloudSession.from)
            cloudChecked = r.num("checked_at"); cloudError = r.str("error")
        } catch { cloudError = error.localizedDescription }
    }

    func loadUsage() async {
        if let r = try? await rpc("usage", ["refresh": false], timeout: 60) { usage = r["accounts"].array.map(UsageAccount.from) }
    }

    /// While the list is visible: memory every 30 s, usage every 120 s. Cancelled with the view's task.
    func pollTriage() async {
        var tick = 0
        while !Task.isCancelled {
            if state == .connected {
                await loadMemory()
                if tick % 4 == 0 { await loadUsage() }
                tick += 1
            }
            try? await Task.sleep(nanoseconds: 30_000_000_000)
        }
    }

    func markAllRead() {
        let waiting = Set(sessions.values.filter { $0.waits }.map(\.key))
        let ids = unread.subtracting(waiting).map { "s-\($0)" }
        unread = []
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: close with undo, rename, kill

    private var closeTasks: [String: Task<Void, Never>] = [:]

    func canClose(_ s: Session) -> Bool { s.alive && !s.exited && !s.background && s.attachable && !s.placeholder }

    /// The row disappears at once; the gateway's `close` runs after 6 s unless `undoClose` comes first. A running app
    /// asks iOS for background time so the close still happens when it goes away meanwhile.
    func softClose(_ s: Session) {
        let key = s.key
        hidden.insert(key)
        undoable = s
        closeTasks[key]?.cancel()
        closeTasks[key] = Task {
            await BackgroundRefresh.withBackgroundTime {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                self.closeTasks[key] = nil
                if self.undoable?.key == key { self.undoable = nil }
                if await self.connectOnce() {
                    do { _ = try await self.rpc("close", ["key": .string(key), "stop": .bool(s.state == "busy")]) }
                    catch { self.lastError = "Nicht geschlossen: \(error.localizedDescription)" }
                } else {
                    self.lastError = "Nicht geschlossen: keine Verbindung"
                }
                self.hidden.remove(key)
                await self.refresh()
                self.releaseBackground()
            }
        }
    }

    func undoClose(_ s: Session) {
        closeTasks[s.key]?.cancel()
        closeTasks[s.key] = nil
        hidden.remove(s.key)
        if undoable?.key == s.key { undoable = nil }
    }

    func rename(_ s: Session, to name: String) async {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        do { try await send(s, text: "/rename \(n)", force: true) } catch { lastError = error.localizedDescription }
    }

    func kill(_ s: Session) async {
        do { _ = try await rpc("kill", ["key": .string(s.key)]); await refresh() }
        catch { lastError = error.localizedDescription }
    }

    // MARK: avatars and offline list

    private func applyConfig(_ config: JSON) {
        guard config.object != nil else { return }
        let live = VoiceMode.isLive(config["voice"].string)
        if live != voiceLive { voiceLive = live }
        var raw: [String: JSON] = [:]
        for k in ["avatars", "avatar_colors", "avatar_topics"] where config.has(k) { raw[k] = config[k] }
        let l = Avatars.look(from: .object(raw))
        if l != look { look = l; avatarLookRaw = JSON.object(raw).serialized() }
    }

    private static var cacheURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("sessions-cache.json")
    }

    private static func loadSessionCache() -> JSON? {
        guard let u = cacheURL, let d = try? Data(contentsOf: u) else { return nil }
        return JSON.parse(d)
    }

    private func saveSessionCache(_ list: JSON) {
        guard let u = Self.cacheURL, let d = list.serialized().data(using: .utf8) else { return }
        try? d.write(to: u, options: .atomic)
    }

    func send(_ s: Session, text: String, force: Bool = false, clientId: String? = nil) async throws {
        var p: [String: JSON] = ["text": .string(text), "enter": true, "force": .bool(force)]
        if let clientId { p["client_id"] = .string(clientId) }
        if s.liveTmux != nil { p["target"] = .string(s.target) } else { p["key"] = .string(s.key) }
        _ = try await rpc("send", .object(p))
    }

    // MARK: Alle Sitzungen beenden (WindDown, Gateway `wind_down`)

    func startWindDown(_ keys: [String]) async throws {
        let r = try await rpc("wind_down", ["keys": JSON(keys), "text": .string(WindDown.message),
                                            "wait_s": .number(Double(WindDown.defaultWaitSeconds))], timeout: 30)
        windDownJob = r.str("job")
        windDownItems = WindDown.items(in: r)
        windDownDone = r.flag("done")
    }

    func refreshWindDown() async {
        guard let job = windDownJob else { return }
        guard let r = try? await rpc("wind_down_status", ["job": .string(job)], timeout: 15), r.str("job") == job else { return }
        windDownItems = WindDown.items(in: r)
        windDownDone = r.flag("done")
    }

    func clearWindDown() { windDownJob = nil; windDownItems = []; windDownDone = false }

    func sendKeys(_ s: Session, _ keys: [String], expectMenu: String? = nil, force: Bool = false) async throws {
        var p: [String: JSON] = ["keys": JSON(keys), "enter": false]
        if force { p["force"] = true }
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
        sessions.values.filter { s in
            if hidden.contains(s.key) || (s.background && !showBackground) { return false }
            let dormant = s.exited || s.closed || s.hibernated
            return showDormant ? dormant : !dormant
        }
    }

    func session(for ref: String) -> Session? {
        sessions[ref] ?? sessions.values.first { $0.matches(ref) && !$0.placeholder } ?? sessions.values.first { $0.matches(ref) }
    }
}

/// Hält die eigene Verbindung für den Ereignis-Rückruf (schwach, damit keine Schleife entsteht).
final class LinkBox: @unchecked Sendable { weak var link: GatewayLink? }
