import SwiftUI
import AVFoundation
import RelayCore

/// Plays a test sentence with a chosen voice.
@MainActor
final class VoiceTester: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let player = PCMPlayer()
    private var sample: Task<Void, Never>?
    /// Supertonic berechnet gerade den Testsatz (beim ersten Mal lädt dabei das Modell).
    @Published private(set) var preparing = false

    override init() { super.init(); synth.delegate = self }

    func test(lang: String) {
        synth.stopSpeaking(at: .immediate)
        sample?.cancel()
        player.stop()
        let text = lang == "de" ? "Hallo, ich bin Jarvis. So klinge ich." : "Hello, I am Jarvis. This is how I sound."
        AudioFocus.takeForPlayback("tester")
        if lang == VoiceModel.language { SupertonicStore.shared.wake() }  // nach Fehlern: neuer Anlauf
        if lang == VoiceModel.language, SupertonicStore.shared.active {
            preparing = true
            sample = Task { [weak self] in
                var pcm: [Float]?
                do { pcm = try await SupertonicStore.shared.synthesize(text) } catch { pcm = nil }
                guard let self else { return }
                self.preparing = false
                if Task.isCancelled { return }
                if let pcm, (try? await self.player.play(pcm)) != nil {
                    self.player.rest()
                    if !Task.isCancelled { self.ended() }
                } else {
                    self.speakApple(text, lang: lang)
                }
            }
            return
        }
        speakApple(text, lang: lang)
    }

    private func speakApple(_ text: String, lang: String) {
        let u = VoiceIO.utterance(text)
        u.voice = SpeechPrefs.voice(lang: lang)
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in self.ended() } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { Task { @MainActor in self.ended() } }
    private func ended() { if !synth.isSpeaking { AudioFocus.release("tester") } }
}

/// Zeile unter „Stimme Deutsch“: Modell von Supertonic 3 laden, Fortschritt, löschen.
struct SupertonicRow: View {
    @ObservedObject private var store = SupertonicStore.shared
    @State private var confirmDelete = false

    /// Zustand des geladenen Modells: startet gerade, pausiert nach Fehlern oder ist bereit.
    private var installedText: String {
        if store.warming {
            return "\(VoiceModel.title) wird gestartet … Beim ersten Mal dauert das länger, so lange spricht die Apple-Stimme."
        }
        if store.resting {
            return "\(VoiceModel.title) hat bei zwei Sätzen nacheinander versagt und pausiert. Bei der nächsten Antwort startet Relay das Modell neu, so lange spricht die Apple-Stimme."
        }
        return "\(VoiceModel.title) ist geladen (\(VoiceModel.sizeText(store.bytes))) und spricht auf dem iPhone, ohne Netz."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch store.phase {
            case .missing:
                Text("\(VoiceModel.title) braucht ein Modell auf dem iPhone (rund 400 MB, einmalig von Hugging Face geladen). Danach spricht Jarvis Deutsch damit, ohne Netz. Bis dahin spricht die Apple-Stimme.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Modell laden") { store.startDownload() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("supertonic.laden")
            case .downloading(let done, let total):
                if total > 0 {
                    ProgressView(value: min(Double(done) / Double(total), 1))
                    Text("\(VoiceModel.sizeText(done)) von \(VoiceModel.sizeText(total)) geladen")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Dateiliste wird abgerufen …").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Abbrechen") { store.cancelDownload() }.buttonStyle(.bordered)
            case .installed:
                Text(installedText)
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Modell löschen", role: .destructive) { confirmDelete = true }.buttonStyle(.bordered)
            case .failed(let why):
                Text(why).font(.footnote).foregroundStyle(.red)
                HStack {
                    Button("Erneut laden") { store.startDownload() }.buttonStyle(.bordered)
                    Button("Modell löschen", role: .destructive) { confirmDelete = true }.buttonStyle(.bordered)
                }
            }
        }
        .confirmationDialog("Modell von \(VoiceModel.title) löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { store.delete() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Jarvis spricht danach wieder mit der Apple-Stimme. Das Modell lässt sich jederzeit neu laden.")
        }
    }
}

/// Settings section "Sprache und Stimme": recognition language, speech language, tempo, voices, reading finished sessions.
struct SpeechSettingsSection: View {
    @AppStorage(SpeechPrefs.recogKey) private var recog = "auto"
    @AppStorage(SpeechPrefs.langKey) private var lang = "auto"
    @AppStorage(SpeechPrefs.tempoKey) private var tempo = 1.0
    @AppStorage(SpeechPrefs.voiceDeKey) private var voiceDe = ""
    @AppStorage(SpeechPrefs.voiceEnKey) private var voiceEn = ""
    @AppStorage(SpeechPrefs.readFinishedKey) private var readFinished = false
    @StateObject private var tester = VoiceTester()
    @ObservedObject private var store = SupertonicStore.shared

    var body: some View {
        Section {
            Picker("Erkennungssprache", selection: $recog) {
                Text("Automatisch").tag("auto")
                Text("Deutsch").tag("de")
                Text("English").tag("en")
            }
            Picker("Sprache der Ausgabe", selection: $lang) {
                Text("Automatisch (je Satz)").tag("auto")
                Text("Deutsch").tag("de")
                Text("English").tag("en")
            }
            VStack(alignment: .leading) {
                Text("Tempo: \(String(format: "%.2f", tempo))")
                Slider(value: $tempo, in: 0.5...1.5, step: 0.05)
            }
            voicePicker("Stimme Deutsch", "de", $voiceDe)
            if voiceDe == VoiceModel.tag || store.phase != .missing { SupertonicRow() }
            voicePicker("Stimme Englisch", "en", $voiceEn)
            Toggle("Fertige Sitzungen vorlesen", isOn: $readFinished)
        } header: {
            Text("Sprache und Stimme")
        } footer: {
            Text("Vorgelesen wird nur mit Kopfhörern oder im Gesprächsmodus, und nur bei geöffneter App. Es werden nur auf dem iPhone installierte Stimmen genutzt, damit nichts an einen Netzwerkdienst geht. \(VoiceModel.title) ist Jarvis' deutsche Stimme: Das Modell wird einmal geladen, gesprochen wird danach auf dem iPhone. Englisch und alles Übrige spricht die Apple-Stimme. Mehr Apple-Stimmen: Einstellungen > Bedienungshilfen > Gesprochene Inhalte > Stimmen.")
        }
    }

    @ViewBuilder
    private func voicePicker(_ title: String, _ code: String, _ selection: Binding<String>) -> some View {
        let all = SpeechPrefs.voices(code)
        HStack {
            Picker(title, selection: selection) {
                Text("Beste vorhandene").tag("")
                if code == VoiceModel.language { Text("\(VoiceModel.title) · auf dem Gerät").tag(VoiceModel.tag) }
                ForEach(all, id: \.identifier) { v in Text(SpeechPrefs.label(v)).tag(v.identifier) }
            }
            if tester.preparing, code == VoiceModel.language { ProgressView() }
            Button("Testen") { tester.test(lang: code) }.buttonStyle(.bordered)
        }
    }
}
