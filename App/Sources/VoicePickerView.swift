import SwiftUI
import AVFoundation
import RelayCore

/// Plays a test sentence with a chosen voice.
@MainActor
final class VoiceTester: ObservableObject {
    private let synth = AVSpeechSynthesizer()

    func test(lang: String) {
        synth.stopSpeaking(at: .immediate)
        let text = lang == "de" ? "Hallo, ich bin Jarvis. So klinge ich." : "Hello, I am Jarvis. This is how I sound."
        let u = VoiceIO.utterance(text)
        u.voice = SpeechPrefs.voice(lang: lang)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synth.speak(u)
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
            voicePicker("Stimme Englisch", "en", $voiceEn)
            Toggle("Fertige Sitzungen vorlesen", isOn: $readFinished)
        } header: {
            Text("Sprache und Stimme")
        } footer: {
            Text("Vorgelesen wird nur mit Kopfhörern oder im Gesprächsmodus, und nur bei geöffneter App. Es werden nur auf dem iPhone installierte Stimmen genutzt, damit nichts an einen Netzwerkdienst geht. Mehr Stimmen: Einstellungen > Bedienungshilfen > Gesprochene Inhalte > Stimmen.")
        }
    }

    @ViewBuilder
    private func voicePicker(_ title: String, _ code: String, _ selection: Binding<String>) -> some View {
        let all = SpeechPrefs.voices(code)
        HStack {
            Picker(title, selection: selection) {
                Text("Beste vorhandene").tag("")
                ForEach(all, id: \.identifier) { v in Text(SpeechPrefs.label(v)).tag(v.identifier) }
            }
            Button("Testen") { tester.test(lang: code) }.buttonStyle(.bordered)
        }
    }
}
