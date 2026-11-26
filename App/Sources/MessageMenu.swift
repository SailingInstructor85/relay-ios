import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import RelayCore

/// Share and save actions for a Desktop file (the file is fetched first).
@MainActor
enum FileActions {
    private static var topController: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.keyWindow?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }

    static func share(_ ref: RemoteRef, onError: @escaping (String) -> Void) {
        Task {
            do {
                let url = try await FileStore.shared.local(ref)
                let v = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                topController?.present(v, animated: true)
            } catch { onError(error.localizedDescription) }
        }
    }

    /// "In Dateien sichern": the system export picker.
    static func save(_ ref: RemoteRef, onError: @escaping (String) -> Void) {
        Task {
            do {
                let url = try await FileStore.shared.local(ref)
                let p = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                topController?.present(p, animated: true)
            } catch { onError(error.localizedDescription) }
        }
    }
}

/// A file of a message as a chip: icon or thumbnail, name, size. Tap opens the viewer, long press offers share, save, copy path.
struct FileChip: View {
    let ref: RemoteRef
    var onOpen: (RemoteRef) -> Void
    var onError: (String) -> Void = { _ in }
    @State private var thumb: UIImage?

    var body: some View {
        Button { onOpen(ref) } label: {
            HStack(spacing: 10) {
                Group {
                    if let thumb {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        Image(systemName: ref.symbol).font(.title3).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.name).font(.footnote.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    let cap = FileKinds.sizeLabel(ref.size)
                    if !cap.isEmpty { Text(cap).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: 320, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { FileActions.share(ref, onError: onError) } label: { Label("Teilen", systemImage: "square.and.arrow.up") }
            Button { FileActions.save(ref, onError: onError) } label: { Label("Sichern", systemImage: "square.and.arrow.down") }
            Button { UIPasteboard.general.string = ref.path } label: { Label("Pfad kopieren", systemImage: "doc.on.doc") }
        }
        .task(id: ref.path) {
            if ref.isImage && ref.size != 0 { thumb = await FileStore.shared.thumb(ref, px: 192) }
        }
        .accessibilityLabel("Datei \(ref.name)")
    }
}

/// Reads a text aloud on demand (ReadAloud.cleaned: no code, paths and links by name). One reader for the whole app,
/// so a new start replaces the old one; pause and resume; the sound goes wherever the phone plays (headset,
/// Bluetooth, speaker). Used by the read buttons of chat messages, notices (Meldungen) and questions (Rückfragen).
///
/// Ist Supertonic als deutsche Stimme gewählt und geladen, spricht es die deutschen Sätze, wie bei Jarvis
/// (`VoiceIO`): Satz für Satz, der Ton der folgenden Sätze wird vorausberechnet, englische Stücke liest die
/// Apple-Stimme. Scheitert ein Satz, spricht ihn die Apple-Stimme (mit Eintrag im Protokoll). Jedes neue Vorlesen
/// gibt Supertonic nach Fehlern einen neuen Anlauf (`SupertonicStore.wake`), es bleibt also nicht dauerhaft bei der
/// Apple-Stimme. Ohne Supertonic liest wie bisher die Apple-Stimme den ganzen Text am Stück.
@MainActor
final class SpeechOut: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechOut()
    /// Something is queued or running (a paused reading counts).
    @Published private(set) var speaking = false
    @Published private(set) var paused = false
    private let synth = AVSpeechSynthesizer()

    // Vorlesen mit Supertonic: die Stücke der Reihe nach
    private var chain: Task<Void, Never>?
    /// Erhöht sich bei jedem Start und Stopp: Was davor begonnen wurde, zählt danach nicht mehr.
    private var round = 0
    /// Ton der folgenden deutschen Sätze, schon berechnet (Schlüssel: Stelle im Text).
    private var prepared: [Int: Task<[Float], Error>] = [:]
    private var player: PCMPlayer?
    private var appleWaiting: (id: ObjectIdentifier, c: CheckedContinuation<Void, Never>)?

    override init() { super.init(); synth.delegate = self }

    func speak(_ markdown: String) {
        halt()  // a new reading replaces the old one without handing the audio back in between
        let text = ReadAloud.cleaned(markdown)
        guard text.rangeOfCharacter(from: .alphanumerics) != nil else { AudioFocus.release("reader"); return }
        AudioFocus.takeForPlayback("reader")
        speaking = true
        paused = false
        let store = SupertonicStore.shared
        store.wake()
        let parts = ReadAloud.parts(text, setting: SpeechPrefs.outputLang)
        guard store.active, parts.contains(where: { $0.lang == VoiceModel.language }) else {
            // Supertonic gewählt und geladen, aber nicht bereit: fürs Protokoll
            if let why = store.idleReason, let first = parts.first(where: { $0.lang == VoiceModel.language }) {
                logFallback(first.text, why)
            }
            synth.speak(VoiceIO.utterance(text))
            return
        }
        let mine = round
        chain = Task { [weak self] in await self?.read(parts, round: mine) }
    }

    func toggle(_ markdown: String) {
        if speaking { stop() } else { speak(markdown) }
    }

    func pause() {
        guard speaking, !paused else { return }
        if chain != nil {
            // Läuft gerade Ton, hält er an. Wird gerade gerechnet, wartet der nächste Satz auf „Weiter“ (`read`).
            paused = true
            if player?.pause() != true, synth.isSpeaking { synth.pauseSpeaking(at: .word) }
        } else if synth.pauseSpeaking(at: .word) {
            paused = true
        }
    }

    func resume() {
        guard paused else { return }
        if chain != nil {
            paused = false
            player?.resume()
            if synth.isPaused { synth.continueSpeaking() }
        } else if synth.continueSpeaking() {
            paused = false
        }
    }

    func stop() {
        halt()
        AudioFocus.release("reader")
    }

    private func halt() {
        round += 1
        chain?.cancel()
        chain = nil
        prepared.values.forEach { $0.cancel() }
        prepared.removeAll()
        player?.stop()
        if synth.isSpeaking || synth.isPaused { synth.stopSpeaking(at: .immediate) }
        if let w = appleWaiting {
            appleWaiting = nil
            w.c.resume()
        }
        speaking = false
        paused = false
    }

    // MARK: Supertonic

    /// Liest die Stücke der Reihe nach: deutsche mit Supertonic, die übrigen (und gescheiterte Sätze) mit der
    /// Apple-Stimme.
    private func read(_ parts: [ReadAloud.Part], round mine: Int) async {
        let store = SupertonicStore.shared
        for (i, part) in parts.enumerated() {
            guard mine == round else { return }
            let ahead = prepared.removeValue(forKey: i)
            var spoken = false
            if part.lang == VoiceModel.language {
                var why: String?
                if store.active {
                    // Ist das Modell noch nicht im Speicher, lädt es beim ersten Satz. Wer auf „Vorlesen“ tippt, wartet
                    // lieber einen Moment auf die gewählte Stimme, als die andere zu hören.
                    let text = part.text
                    let task = ahead ?? Task { try await store.synthesize(text) }
                    prepareAhead(parts, after: i)
                    do {
                        let pcm = try await task.value
                        guard await unpaused(round: mine) else { return }
                        if player == nil { player = PCMPlayer() }
                        try await player?.play(pcm)
                        spoken = true
                    } catch {
                        why = (error as? RelayErrorText)?.text ?? "\(error)"
                    }
                } else {
                    ahead?.cancel()
                    why = store.idleReason
                }
                guard mine == round else { return }
                if !spoken, let why { logFallback(part.text, why) }
            } else {
                ahead?.cancel()
            }
            if !spoken {
                guard await unpaused(round: mine) else { return }
                await speakWithApple(part.text)
            }
        }
        guard mine == round else { return }
        chain = nil
        player?.rest()
        speaking = false
        paused = false
        AudioFocus.release("reader")
    }

    /// Wartet, solange pausiert ist. false: Inzwischen wurde gestoppt oder etwas anderes vorgelesen.
    private func unpaused(round mine: Int) async -> Bool {
        while paused, mine == round {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return mine == round
    }

    /// Berechnet den Ton der folgenden deutschen Sätze voraus (höchstens `VoiceCompute.ahead`).
    private func prepareAhead(_ parts: [ReadAloud.Part], after index: Int) {
        let store = SupertonicStore.shared
        guard store.active, index + 1 < parts.count else { return }
        for i in (index + 1)..<parts.count where parts[i].lang == VoiceModel.language && prepared[i] == nil {
            if prepared.count >= VoiceCompute.ahead { break }
            let text = parts[i].text
            prepared[i] = Task { try await store.synthesize(text) }
        }
    }

    private func speakWithApple(_ text: String) async {
        let u = VoiceIO.utterance(text)
        let id = ObjectIdentifier(u)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            appleWaiting = (id, c)
            synth.speak(u)
        }
    }

    private func logFallback(_ text: String, _ why: String) {
        let front = UIApplication.shared.applicationState != .background
        AppLog.shared.log("info", "supertonic", "Vorlesen: " + VoiceCompute.fallbackLine(sentence: text, reason: why, foreground: front), keep: true)
    }

    // MARK: Apple-Stimme

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        // den Satz bis zur Verarbeitung festhalten: so kann ein neuer Satz nicht dieselbe Kennung (Adresse) bekommen
        nonisolated(unsafe) let utt = u
        Task { @MainActor in self.ended(ObjectIdentifier(utt)) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        nonisolated(unsafe) let utt = u
        Task { @MainActor in self.ended(ObjectIdentifier(utt)) }
    }

    /// Die Apple-Stimme meldet ein Stück als fertig oder abgebrochen. In der Kette geht es mit dem nächsten Stück
    /// weiter. Ohne Kette ist der ganze Text gelesen: the audio goes back to other apps (Spotify resumes).
    private func ended(_ id: ObjectIdentifier) {
        if let w = appleWaiting {
            guard w.id == id else { return }  // Nachzügler eines abgebrochenen Stücks
            appleWaiting = nil
            w.c.resume()
            return
        }
        guard chain == nil, !synth.isSpeaking else { return }  // a new reading has already started
        speaking = false; paused = false
        AudioFocus.release("reader")
    }
}

/// Pause, resume and stop while something is read aloud (shown above the input bar of a chat).
struct ReadAloudBar: View {
    @ObservedObject var reader: SpeechOut
    var body: some View {
        HStack(spacing: 12) {
            Label(reader.paused ? "Vorlesen pausiert" : "Liest vor…", systemImage: reader.paused ? "pause.circle" : "speaker.wave.2")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button { reader.paused ? reader.resume() : reader.pause() } label: { Image(systemName: reader.paused ? "play.fill" : "pause.fill") }
                .accessibilityLabel(reader.paused ? "Weiter vorlesen" : "Vorlesen pausieren").accessibilityIdentifier("readPause")
            Button { reader.stop() } label: { Image(systemName: "stop.fill") }
                .accessibilityLabel("Vorlesen beenden").accessibilityIdentifier("readStop")
        }
        .padding(.horizontal).padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }
}

/// Selectable full-screen text (UITextView: handles, select all, copy).
struct SelectableText: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.font = UIFont.preferredFont(forTextStyle: .body)
        v.adjustsFontForContentSizeCategory = true
        v.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        v.text = text
        return v
    }
    func updateUIView(_ v: UITextView, context: Context) { if v.text != text { v.text = text } }
}

/// Long press on a message: copy, select text, read aloud, its links and files.
struct MessageMenu: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let message: TMessage
    let base: String?
    let onFile: (RemoteRef) -> Void

    @ObservedObject private var speech = SpeechOut.shared
    @State private var copied = ""
    @State private var error: String?

    private var links: [FoundLink] { Array(Links.extract(message.text).prefix(30)) }
    /// The question of this message with options and recommendation, when it asks one (ReadAloud).
    private var question: String? { message.role == "assistant" ? ReadAloud.question(in: message.text) : nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { UIPasteboard.general.string = message.text; flash("Kopiert") } label: { Label("Kopieren", systemImage: "doc.on.doc") }
                    NavigationLink { SelectableText(text: message.text).navigationTitle("Text auswählen").navigationBarTitleDisplayMode(.inline) } label: {
                        Label("Text auswählen", systemImage: "selection.pin.in.out")
                    }
                    Button { speech.toggle(message.text) } label: {
                        Label(speech.speaking ? "Vorlesen beenden" : "Vorlesen", systemImage: speech.speaking ? "speaker.slash" : "speaker.wave.2")
                    }
                    if let question {
                        Button { speech.speak(question); dismiss() } label: { Label("Frage vorlesen", systemImage: "questionmark.bubble") }
                    }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
                if !links.isEmpty {
                    Section("Links") {
                        ForEach(links, id: \.target) { l in
                            Button { open(l.target) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.label).lineLimit(2)
                                    if l.label != l.target { Text(l.target).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                                }
                            }
                            .contextMenu {
                                Button { UIPasteboard.general.string = l.target; flash("Link kopiert") } label: { Label("Link kopieren", systemImage: "doc.on.doc") }
                            }
                            .swipeActions { Button { UIPasteboard.general.string = l.target; flash("Link kopiert") } label: { Label("Kopieren", systemImage: "doc.on.doc") }.tint(.blue) }
                        }
                    }
                }
                if !message.files.isEmpty {
                    Section("Dateien") {
                        ForEach(message.files, id: \.path) { f in
                            FileChip(ref: RemoteRef(f), onOpen: { r in dismiss(); onFile(r) }, onError: { error = $0 })
                        }
                    }
                }
            }
            .navigationTitle(copied.isEmpty ? "Nachricht" : copied)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func open(_ raw: String) {
        LinkRouter.open(raw, base: base, onFile: { r in dismiss(); onFile(r) }, onError: { error = $0 })
    }

    private func flash(_ t: String) {
        copied = t
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = "" }
    }
}
