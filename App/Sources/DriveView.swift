import SwiftUI
import UIKit
import Combine
import AVFoundation
import RelayCore

/// Führt den Sprachmodus aus (`DriveSession` in RelayCore): liest vor, hört zu, schickt Antworten an `rueckfrage`.
/// Knöpfe und neue Rückfragen unterbrechen das Vorlesen oder Zuhören und geben den nächsten Schritt vor.
@MainActor
final class DriveController: ObservableObject {
    @Published private(set) var drive = DriveSession()
    /// Läuft gerade ein Gespräch mit einer Sitzung, hat es Vorrang; neue Rückfragen warten so lange.
    @Published private(set) var talk: DriveTalk?
    /// Was zuletzt vorgelesen wurde (steht groß auf dem Bildschirm).
    @Published private(set) var said = ""
    /// Was zuletzt verstanden wurde.
    @Published private(set) var heard = ""
    @Published private(set) var sending = false
    @Published var error: String?
    let voice = VoiceIO()

    /// Ein Schritt des Ablaufs, aus `DriveEffect` (Rückfragen) oder `TalkEffect` (Gespräch).
    private enum Step {
        case say(String), listen, answer(ref: String, text: String), message(String), awaitReply
    }

    private var loop: Task<Void, Never>?
    private var pending: [Step]?
    private var tapWait: CheckedContinuation<Void, Never>?
    private var micAllowed = false
    private var prepared = false
    /// Die Ansicht ist zu: der Ablauf endet nach dem laufenden Schritt, ohne weiter zu sprechen oder zuzuhören.
    private var closed = false
    private var voiceChanges: AnyCancellable?
    /// Längste Wartezeit auf die Antwort einer Sitzung.
    static let replyLimit: TimeInterval = 15 * 60

    init() {
        // Zuhören und Vorlesen ändern die Anzeige (Statuszeile, Teiltext)
        voiceChanges = voice.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// Im UI-Test ohne Mikrofon und Stimme: Zuhören wartet auf einen Knopf.
    private var quiet: Bool { UITestMode.active }

    /// Beim Öffnen und beim Zurückkommen (etwa aus Jarvis): der Modus beginnt neu mit den offenen Rückfragen.
    func start(_ notices: [Notice]) async {
        guard !drive.isActive else { return }
        closed = false
        if !prepared && !quiet {
            prepared = true
            if let msg = await voice.authorize() { error = msg + " Antworte mit den Knöpfen." } else { micAllowed = true }
            await AppModel.shared.loadVocab(into: voice)
        }
        run(drive.start(DriveQueue.open(notices)))
    }

    /// Neue oder anderswo beantwortete Rückfragen (während eines Gesprächs erst danach).
    func sync(_ notices: [Notice]) {
        guard drive.isActive, talk == nil else { return }
        let open = DriveQueue.open(notices)
        let openRefs = Set(open.map(\.ref))
        var effects: [DriveEffect] = []
        for item in drive.queue where !openRefs.contains(item.ref) { effects += drive.drop(ref: item.ref) }
        effects += drive.enqueue(open)
        run(effects)
    }

    func tap(_ c: DriveCommand) {
        if talk != nil { talkRun(talk!.command(c)) } else { run(drive.command(c)) }
    }
    func resume() { run(drive.resume()) }

    /// Gespräch mit einer Sitzung beginnen (nur, wenn gerade keine Rückfrage vorgelesen wird).
    func startTalk(_ s: Session) {
        guard talk == nil, drive.phase == .waiting || drive.phase == .paused else { return }
        var t = DriveTalk(key: s.key, name: s.name)
        let e = t.start()
        talk = t
        talkRun(e)
    }

    /// Beim Verlassen der Ansicht: sofort still, Audio frei für andere Apps.
    func shutdown() {
        closed = true
        _ = drive.stop()
        talk = nil
        pending = nil
        interrupt()
        releaseAudio()
    }

    private func run(_ effects: [DriveEffect]) {
        enqueue(effects.map { e -> Step in
            switch e {
            case .say(let t): return .say(t)
            case .listen: return .listen
            case .send(let ref, let text): return .answer(ref: ref, text: text)
            }
        })
    }

    private func talkRun(_ effects: [TalkEffect]) {
        enqueue(effects.map { e -> Step in
            switch e {
            case .say(let t): return .say(t)
            case .listen: return .listen
            case .send(let t): return .message(t)
            case .awaitReply: return .awaitReply
            }
        })
    }

    private func enqueue(_ steps: [Step]) {
        guard !steps.isEmpty else { return }
        pending = steps
        if loop == nil { loop = Task { await process() } } else { interrupt() }
    }

    private func interrupt() {
        voice.stopSpeaking()
        voice.stopListening()
        tapWait?.resume()
        tapWait = nil
    }

    /// Ein beendetes Gespräch macht Platz: zurück zu den Rückfragen, neue werden jetzt vorgelesen.
    private func finishTalkIfEnded() {
        guard let t = talk, !t.isActive else { return }
        talk = nil
        let rest = pending
        pending = nil
        sync(NoticeStore.shared.items)
        if let rest { pending = rest + (pending ?? []) }
    }

    private func process() async {
        defer { loop = nil }
        while !closed, let steps = pending {
            pending = nil
            flow: for step in steps {
                if pending != nil || closed { break flow }
                switch step {
                case .say(let t):
                    said = t
                    if !quiet { voice.speak(ReadAloud.cleaned(t)); await voice.waitUntilSpoken() }
                case .listen:
                    heard = ""
                    let h = await hear()
                    if pending != nil || closed || !drive.isActive { break flow }
                    heard = h
                    if !h.isEmpty { UsageRecorder.shared.content("sprachmodus", "gesprochen", session: talk?.key, kind: "sprache", text: h) }
                    if talk != nil { let e = talk!.heard(h); talkRun(e) } else { run(drive.heard(h)) }
                case .answer(let ref, let text):
                    sending = true
                    let err = await AppModel.shared.answerQuestion(ref: ref, text: text)
                    sending = false
                    run(drive.sent(error: err))
                case .message(let text):
                    sending = true
                    let err = await sendToSession(text)
                    sending = false
                    if talk != nil { let e = talk!.sent(error: err); talkRun(e) }
                case .awaitReply:
                    let reply = await waitForReply()
                    if pending != nil || closed || talk?.isActive != true { break flow }
                    let e = talk!.replied(reply)
                    talkRun(e)
                }
            }
            finishTalkIfEnded()
        }
        // nichts mehr vorzulesen: Musik und Navigation wieder in voller Lautstärke
        if pending == nil || closed { releaseAudio() }
    }

    private func sendToSession(_ text: String) async -> String? {
        let m = AppModel.shared
        guard let key = talk?.key, let s = m.session(for: key) else { return "Die Sitzung gibt es nicht mehr." }
        do { try await m.send(s, text: text) } catch { return error.localizedDescription }
        UsageRecorder.shared.content("sprachmodus", "gesendet", session: key, kind: "sprache", text: text)
        return nil
    }

    /// Wartet, bis die Sitzung zu arbeiten beginnt und wieder fertig ist (oder auf Eingabe wartet), und gibt die
    /// gekürzte Antwort zurück; nil nach `replyLimit` oder wenn das Gespräch beendet wurde.
    private func waitForReply() async -> String? {
        guard let key = talk?.key else { return nil }
        let m = AppModel.shared
        let begin = Date()
        let before = m.session(for: key)?.lastActivity ?? 0
        var sawBusy = false
        while !closed, pending == nil, talk?.isActive == true, Date().timeIntervalSince(begin) < Self.replyLimit {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let s = m.session(for: key) else { return nil }
            if s.state == "busy" { sawBusy = true; continue }
            // fertig: sie hat gearbeitet, oder es kam ohne sichtbares „busy“ schon neue Aktivität
            let done = sawBusy || (s.lastActivity > before && Date().timeIntervalSince(begin) > 3)
            if !done { continue }
            var summary: String?
            if !quiet { summary = try? await m.summarize(s) }
            let now = m.session(for: key) ?? s
            return DriveTalk.spokenReply(summary: summary, lastMessage: now.lastMessage, question: now.waits ? now.question : nil)
        }
        return nil
    }

    /// Zuhören, oder ohne Mikrofon auf einen Knopf warten ("" = nichts gehört).
    private func hear() async -> String {
        if quiet || !micAllowed {
            await withCheckedContinuation { c in tapWait = c }
            return ""
        }
        do { return try await voice.listen() } catch {
            self.error = error.localizedDescription
            return ""
        }
    }

    private func releaseAudio() {
        guard !quiet, !voice.speaking, !voice.listening else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Sprachmodus („Autofahrt“): liest offene Rückfragen vor, nimmt die Antwort per Sprache, liest sie zur Kontrolle vor
/// und schickt sie erst nach „senden“. Große Knöpfe für alles, was man auch sagen kann. Der Bildschirm bleibt an,
/// solange die Ansicht offen ist.
struct DriveView: View {
    @StateObject private var c = DriveController()
    @ObservedObject private var store = NoticeStore.shared
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var voice: VoiceIO { c.voice }

    var body: some View {
        VStack(spacing: 16) {
            status
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let t = c.talk {
                        Text("Gespräch mit \(t.name)").font(.headline).foregroundStyle(.secondary)
                        Text(c.said).font(.title3)
                        if case .confirming(let text) = t.phase {
                            Text("Deine Nachricht: \(text)").font(.title2.weight(.semibold)).foregroundStyle(Color.accentColor)
                        }
                    } else if let item = c.drive.current, c.drive.phase != .waiting {
                        Text("\(item.question.id) von \(item.question.agent)").font(.headline).foregroundStyle(.secondary)
                        Text(item.question.question).font(.title2.weight(.semibold)).accessibilityIdentifier("driveQuestion")
                        if !item.question.recommendation.isEmpty {
                            Text("Empfehlung: \(item.question.recommendation)").font(.title3)
                        }
                    } else {
                        Text(c.said.isEmpty ? "Sprachmodus startet…" : c.said).font(.title3).foregroundStyle(.secondary)
                    }
                    if case .confirming(let a) = c.drive.phase {
                        Text("Deine Antwort: \(a)").font(.title2.weight(.semibold)).foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("driveAnswer")
                    }
                    if voice.listening {
                        Text(voice.partial.isEmpty ? "Ich höre…" : voice.partial).font(.title3).italic().foregroundStyle(.secondary)
                    }
                    if let e = c.error { Text(e).font(.footnote).foregroundStyle(.red) }
                    if c.talk == nil, c.drive.phase == .waiting || c.drive.phase == .paused { talkChoices }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            buttons
        }
        .padding()
        .navigationTitle("Sprachmodus")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Beenden") { c.shutdown(); dismiss() }.accessibilityIdentifier("driveEnd")
            }
        }
        .task { await c.start(store.items) }
        .onChange(of: store.items) { _, items in c.sync(items) }
        .onAppear {
            UsageRecorder.shared.screen("sprachmodus")
            model.driveActive = true
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            c.shutdown()
            model.driveActive = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var status: some View {
        HStack {
            Image(systemName: icon).symbolEffect(.pulse, isActive: voice.listening || voice.speaking)
            Text(statusText)
            Spacer()
            let n = c.drive.queue.count
            if n > 0 { Text(n == 1 ? "1 offen" : "\(n) offen").foregroundStyle(.secondary) }
        }
        .font(.headline)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("driveStatus")
    }

    private var icon: String {
        if c.sending { return "paperplane" }
        if voice.listening { return "mic.fill" }
        if voice.speaking { return "speaker.wave.2.fill" }
        return "car"
    }

    private var statusText: String {
        if c.sending { return "Sende…" }
        if let t = c.talk {
            switch t.phase {
            case .dictating: return voice.speaking ? "Liest vor" : "Was soll ich sagen?"
            case .confirming: return voice.speaking ? "Liest Nachricht vor" : "Senden oder nochmal?"
            case .sending: return "Sende…"
            case .working: return voice.speaking ? "Liest vor" : "\(t.name) arbeitet"
            case .idle, .ended: return "Gespräch beendet"
            }
        }
        switch c.drive.phase {
        case .idle: return "Startet"
        case .answering: return voice.speaking ? "Liest vor" : "Deine Antwort?"
        case .confirming: return voice.speaking ? "Liest Antwort vor" : "Senden oder nochmal?"
        case .sending: return "Sende…"
        case .paused: return "Pausiert"
        case .waiting: return "Wartet auf Rückfragen"
        case .stopped: return "Aus"
        }
    }

    /// Laufende Sitzungen, zuletzt aktive zuerst (höchstens vier), dazu Jarvis.
    @ViewBuilder private var talkChoices: some View {
        let live = model.sessions.values
            .filter { $0.alive && !$0.exited && !$0.background && !$0.closed && !$0.placeholder }
            .sorted { $0.lastActivity > $1.lastActivity }
            .prefix(4)
        VStack(alignment: .leading, spacing: 8) {
            Text("Mit einer Sitzung sprechen").font(.headline).padding(.top, 8)
            ForEach(Array(live)) { s in
                Button { c.startTalk(s) } label: {
                    Label(s.name, systemImage: "bubble.left.and.bubble.right").font(.title3).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            if live.isEmpty { Text("Keine laufende Sitzung.").foregroundStyle(.secondary) }
            NavigationLink(value: SessionsView.Dest.jarvisListening) {
                Label("Mit Jarvis sprechen", systemImage: "waveform").font(.title3).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
    }

    /// Große Knöpfe passend zum Schritt; was man sagen kann, geht auch per Tipp.
    @ViewBuilder private var buttons: some View {
        if let t = c.talk { talkButtons(t) } else { driveButtons }
    }

    @ViewBuilder private func talkButtons(_ t: DriveTalk) -> some View {
        if case .confirming = t.phase {
            HStack(spacing: 12) {
                big("Senden", "paperplane.fill", .green, id: "talkSend") { c.tap(.send) }
                big("Nochmal", "mic", .orange, id: "talkRetry") { c.tap(.retry) }
            }
        }
        big("Gespräch beenden", "xmark", .gray, id: "talkEnd") { c.tap(.stop) }
    }

    @ViewBuilder private var driveButtons: some View {
        switch c.drive.phase {
        case .answering:
            HStack(spacing: 12) {
                big("Ja", "checkmark", .green, id: "driveYes") { c.tap(.accept) }
                big("Nein", "xmark", .red, id: "driveNo") { c.tap(.decline) }
            }
            HStack(spacing: 12) {
                big("Wiederholen", "arrow.counterclockwise", .gray, id: "driveRepeat") { c.tap(.repeatQuestion) }
                big("Später", "forward", .gray, id: "driveSkip") { c.tap(.skip) }
            }
        case .confirming:
            HStack(spacing: 12) {
                big("Senden", "paperplane.fill", .green, id: "driveSend") { c.tap(.send) }
                big("Nochmal", "mic", .orange, id: "driveRetry") { c.tap(.retry) }
            }
            big("Später", "forward", .gray, id: "driveSkip") { c.tap(.skip) }
        case .paused:
            big("Sprechen", "mic.fill", .accentColor, id: "driveResume") { c.resume() }
        case .sending:
            ProgressView().controlSize(.large).frame(height: 72)
        case .stopped:
            big("Neu starten", "car", .accentColor, id: "driveRestart") { Task { await c.start(store.items) } }
        default:
            EmptyView()
        }
    }

    private func big(_ title: String, _ symbol: String, _ color: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .accessibilityIdentifier(id)
    }
}
