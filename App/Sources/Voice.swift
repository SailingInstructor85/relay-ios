import Foundation
import AVFoundation
import Speech
import NaturalLanguage

/// Speech in and out for Jarvis: on-device recognition (SFSpeechRecognizer) with the gateway's vocabulary, and
/// spoken replies sentence by sentence while the answer streams in (AVSpeechSynthesizer).
@MainActor
final class VoiceIO: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var listening = false
    @Published private(set) var speaking = false
    @Published private(set) var partial = ""

    var terms: [String] = []
    var corrections: [(heard: String, meant: String)] = []

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finishListening: CheckedContinuation<String, Never>?
    private var lastHeard = Date()
    private var started = Date()
    private var watchdog: Task<Void, Never>?

    private let synth = AVSpeechSynthesizer()
    private var pendingUtterances = 0
    private var speechBuffer = ""
    private var speakWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: permissions

    /// nil when speech recognition and the microphone may be used, else a message for the user.
    func authorize() async -> String? {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { return "Spracherkennung ist nicht erlaubt (Einstellungen → Relay)." }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { return "Mikrofon ist nicht erlaubt (Einstellungen → Relay)." }
        return nil
    }

    // MARK: listening

    /// Records until the speaker pauses (1.6 s after the last recognised word), `stopListening()` is called, nothing is
    /// heard for 7 s, or 45 s pass. Returns the recognised text with the gateway's corrections applied ("" = nothing).
    func listen(locale: String = "de-DE") async throws -> String {
        stopSpeaking()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            throw RelayErrorText("Spracherkennung für \(locale) ist gerade nicht verfügbar.")
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.addsPunctuation = true
        req.contextualStrings = Array(terms.prefix(100))
        request = req

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        Self.installTap(on: input, into: req)
        engine.prepare()
        try engine.start()

        partial = ""
        listening = true
        started = Date()
        lastHeard = Date()
        task = Self.recognize(recognizer, req) { [weak self] text, final in
            guard let self else { return }
            if let text, !text.isEmpty { self.partial = text; self.lastHeard = Date() }
            if final { self.endListening() }
        }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, self.listening else { return }
                let now = Date()
                let heardSomething = !self.partial.isEmpty
                if heardSomething && now.timeIntervalSince(self.lastHeard) > 1.6 { self.endListening(); return }
                if !heardSomething && now.timeIntervalSince(self.started) > 7 { self.endListening(); return }
                if now.timeIntervalSince(self.started) > 45 { self.endListening(); return }
            }
        }
        let text = await withCheckedContinuation { c in finishListening = c }
        return applyCorrections(text)
    }

    func stopListening() { endListening() }

    private func endListening() {
        guard listening else { return }
        listening = false
        watchdog?.cancel(); watchdog = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        let text = partial
        finishListening?.resume(returning: text)
        finishListening = nil
    }

    /// Built outside the main actor: the audio tap runs on a realtime thread.
    nonisolated private static func installTap(on node: AVAudioInputNode, into req: SFSpeechAudioBufferRecognitionRequest) {
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
    }

    nonisolated private static func recognize(_ r: SFSpeechRecognizer, _ req: SFSpeechAudioBufferRecognitionRequest,
                                              _ onResult: @escaping @MainActor (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        r.recognitionTask(with: req) { result, error in
            let text = result?.bestTranscription.formattedString
            let final = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in onResult(text, final) }
        }
    }

    func applyCorrections(_ s: String) -> String {
        var out = s
        for c in corrections where !c.heard.isEmpty {
            out = out.replacingOccurrences(of: c.heard, with: c.meant, options: [.caseInsensitive])
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: speaking

    /// Feeds streamed answer text; complete sentences are spoken at once, the rest waits for more text or `flush()`.
    func feed(_ delta: String) {
        speechBuffer += delta
        while let r = speechBuffer.range(of: #"[.!?:;]\s|\n"#, options: .regularExpression) {
            let sentence = String(speechBuffer[..<r.upperBound])
            speechBuffer = String(speechBuffer[r.upperBound...])
            say(sentence)
        }
    }

    func flush() {
        let rest = speechBuffer
        speechBuffer = ""
        say(rest)
    }

    func speak(_ text: String) { speechBuffer = ""; feed(text); flush() }

    func stopSpeaking() {
        speechBuffer = ""
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        pendingUtterances = 0
        speaking = false
        resumeSpeakWaiters()
    }

    /// Returns once everything queued has been spoken (or speaking was stopped).
    func waitUntilSpoken() async {
        if pendingUtterances == 0 && speechBuffer.isEmpty { return }
        await withCheckedContinuation { c in speakWaiters.append(c) }
    }

    private func say(_ raw: String) {
        let text = Self.speakable(raw)
        guard text.rangeOfCharacter(from: .alphanumerics) != nil else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice(for: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        pendingUtterances += 1
        speaking = true
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    private func utteranceEnded() {
        pendingUtterances = max(0, pendingUtterances - 1)
        if pendingUtterances == 0 {
            speaking = false
            if speechBuffer.isEmpty { resumeSpeakWaiters() }
        }
    }

    private func resumeSpeakWaiters() {
        let w = speakWaiters
        speakWaiters = []
        w.forEach { $0.resume() }
    }

    /// Markdown and code out, so the voice doesn't read asterisks and backticks.
    static func speakable(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"```[\s\S]*?```"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"https?://\S+"#, with: "Link", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[*_`#>|]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^\s*[-•]\s+"#, with: "", options: [.regularExpression])
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.german, .english]
        r.processString(text)
        let lang = (r.dominantLanguage == .english && text.count > 12) ? "en" : "de"
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang) }
        let preferred = lang == "de" ? "de-DE" : "en-US"
        return candidates.filter { $0.language == preferred }.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? candidates.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: preferred)
    }
}

struct RelayErrorText: LocalizedError {
    let text: String
    init(_ t: String) { text = t }
    var errorDescription: String? { text }
}
