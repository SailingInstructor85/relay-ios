import Foundation
import AVFoundation
import Speech
import RelayCore

/// Speech in and out for Jarvis: on-device recognition (SFSpeechRecognizer) with the gateway's vocabulary, and
/// spoken replies sentence by sentence while the answer streams in (AVSpeechSynthesizer).
@MainActor
final class VoiceIO: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var listening = false
    @Published private(set) var speaking = false
    @Published private(set) var partial = ""

    var terms: [String] = []
    var corrections: [(heard: String, meant: String)] = []
    private var hyps: [String] = []
    private var hypConf: [Float] = []

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finishListening: CheckedContinuation<String, Never>?
    private var lastHeard = Date()
    private var started = Date()
    private var watchdog: Task<Void, Never>?
    private var recognizer: SFSpeechRecognizer?
    private let sink = RequestSink()
    private var segment = 0
    private var segmentText = ""
    private var committed = ""
    private var restarts = 0
    /// UI-Test: kein Mikrofon im Simulator, `listen` „hört“ `JarvisDictation.uiTestPhrase`, bis ein Knopf es beendet.
    private var fake = false

    private let synth = AVSpeechSynthesizer()
    private var pendingUtterances = 0
    private var splitter = SentenceSplitter()
    private var speakWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: permissions

    /// nil when speech recognition and the microphone may be used, else a message for the user.
    func authorize() async -> String? {
        if UITestMode.active { return nil }  // no permission dialogs in UI tests; listen() fakes the recording
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { return "Spracherkennung ist nicht erlaubt (Einstellungen → Relay)." }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { return "Mikrofon ist nicht erlaubt (Einstellungen → Relay)." }
        return nil
    }

    // MARK: listening

    /// Pause after the last recognised word that ends the recording (time to think mid-sentence).
    static let pauseLimit: TimeInterval = 3
    /// Ends the recording when nothing at all is recognised this long after the start.
    static let silentStartLimit: TimeInterval = 10

    /// Records until the speaker pauses (`pauseLimit` after the last recognised word), `stopListening()` is called, or
    /// nothing is heard for `silentStartLimit`. No overall cap: when the recogniser ends a segment on its own (its time
    /// limit, an error) a new one starts on the same audio and the text is appended. Returns the recognised text with
    /// the gateway's corrections applied ("" = nothing). A `listen` still open from an earlier call (a second tap before
    /// the first one got going) is ended first with what it has, so no caller waits forever.
    func listen(locale: String? = nil) async throws -> String {
        if listening || finishListening != nil { endListening() }
        stopSpeaking()
        if UITestMode.active { return await fakeListen() }
        let locale = locale ?? SpeechPrefs.recognitionLocale
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            throw RelayErrorText("Spracherkennung für \(locale) ist gerade nicht verfügbar.")
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        self.recognizer = recognizer
        committed = ""
        partial = ""
        hyps = []; hypConf = []
        restarts = 0
        startSegment()

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        Self.installTap(on: input, into: sink)
        engine.prepare()
        do { try engine.start() } catch { abortSegment(); throw error }

        listening = true
        started = Date()
        lastHeard = Date()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, self.listening else { return }
                let now = Date()
                let heardSomething = !self.partial.isEmpty
                if heardSomething && now.timeIntervalSince(self.lastHeard) > Self.pauseLimit { self.endListening(); return }
                if !heardSomething && now.timeIntervalSince(self.started) > Self.silentStartLimit { self.endListening(); return }
            }
        }
        let text = await withCheckedContinuation { c in finishListening = c }
        return applyCorrections(text)
    }

    func stopListening() { endListening() }

    private func fakeListen() async -> String {
        fake = true
        committed = ""; partial = ""; segmentText = ""; hyps = []; hypConf = []
        listening = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, self.listening, self.fake else { return }
            self.segmentText = JarvisDictation.uiTestPhrase
            self.partial = JarvisDictation.uiTestPhrase
        }
        let text = await withCheckedContinuation { c in finishListening = c }
        return applyCorrections(text)
    }

    /// A fresh recognition request and task; the audio tap feeds whichever request `sink` holds.
    private func startSegment() {
        guard let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.addsPunctuation = true
        req.contextualStrings = SpeechVocab.biasing(terms)
        request = req
        sink.set(req)
        segment += 1
        let id = segment
        segmentText = ""
        hyps = []; hypConf = []
        task = Self.recognize(recognizer, req) { [weak self] text, alts, conf, final in
            guard let self, self.listening, id == self.segment else { return }  // a stale callback of an older segment
            if let text, !text.isEmpty {
                // the recogniser started over after a pause (no `isFinal`): keep what it had before
                if DictationText.restarted(previous: self.segmentText, current: text) {
                    self.committed = Self.join(self.committed, self.bestSegmentText())
                }
                self.segmentText = text; self.hyps = alts; self.hypConf = conf
                self.partial = Self.join(self.committed, text)
                self.lastHeard = Date()
                self.restarts = 0
            }
            if final { self.segmentEnded() }
        }
    }

    /// The recogniser ended a segment while the user still speaks or thinks: keep its text, go on with a new one.
    /// Gives up after a few segments in a row that recognised nothing (a recogniser that fails at once).
    private func segmentEnded() {
        committed = Self.join(committed, bestSegmentText())
        request?.endAudio()
        task?.cancel()
        restarts += 1
        if restarts > 3 { endListening(); return }
        startSegment()
    }

    private func bestSegmentText() -> String {
        SpeechVocab.pick(hyps, conf: hypConf, terms: SpeechVocab.scoringTerms(terms: terms, corrections: corrections)) ?? segmentText
    }

    private func abortSegment() {
        sink.set(nil)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
    }

    /// Ends the recording and hands the text to `listen()`; also wakes a `listen()` whose recording never started.
    private func endListening() {
        guard listening || finishListening != nil else { return }
        listening = false
        watchdog?.cancel(); watchdog = nil
        if fake {
            fake = false
        } else {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        let text = Self.join(committed, bestSegmentText())
        abortSegment()
        finishListening?.resume(returning: text)
        finishListening = nil
    }

    private static func join(_ a: String, _ b: String) -> String { DictationText.join(a, b) }

    /// Built outside the main actor: the audio tap runs on a realtime thread.
    nonisolated private static func installTap(on node: AVAudioInputNode, into sink: RequestSink) {
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in sink.append(buffer) }
    }

    nonisolated private static func recognize(_ r: SFSpeechRecognizer, _ req: SFSpeechAudioBufferRecognitionRequest,
                                              _ onResult: @escaping @MainActor (String?, [String], [Float], Bool) -> Void) -> SFSpeechRecognitionTask {
        r.recognitionTask(with: req) { result, error in
            let text = result?.bestTranscription.formattedString
            let alts = result?.transcriptions.map(\.formattedString) ?? []
            let conf: [Float] = result?.transcriptions.map { t in
                t.segments.isEmpty ? 0 : t.segments.map(\.confidence).reduce(0, +) / Float(t.segments.count)
            } ?? []
            let final = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in onResult(text, alts, conf, final) }
        }
    }

    func applyCorrections(_ s: String) -> String {
        SpeechVocab.correct(s, corrections).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: speaking

    /// Feeds streamed answer text; complete sentences are spoken at once, the rest waits for more text or `flush()`.
    func feed(_ delta: String) {
        for sentence in splitter.add(delta) { say(sentence) }
    }

    func flush() {
        if let rest = splitter.end() { say(rest) }
    }

    func speak(_ text: String) { splitter.reset(); feed(text); flush() }

    func stopSpeaking() {
        splitter.reset()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        pendingUtterances = 0
        speaking = false
        resumeSpeakWaiters()
    }

    /// Returns once everything queued has been spoken (or speaking was stopped).
    func waitUntilSpoken() async {
        if pendingUtterances == 0 && splitter.isEmpty { return }
        await withCheckedContinuation { c in speakWaiters.append(c) }
    }

    private func say(_ raw: String) {
        let text = Self.speakable(raw)
        guard text.rangeOfCharacter(from: .alphanumerics) != nil else { return }
        let u = Self.utterance(text)
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
            if splitter.isEmpty { resumeSpeakWaiters() }
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

    /// An utterance with the chosen voice, language (per sentence when "auto") and tempo.
    static func utterance(_ text: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = SpeechPrefs.voice(for: text)
        let rate = AVSpeechUtteranceDefaultSpeechRate * Float(SpeechPrefs.tempo)
        u.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        return u
    }
}

/// Settings of speech in and out (UserDefaults; the settings view uses the same keys through `@AppStorage`).
enum SpeechPrefs {
    static let recogKey = "speechRecog", langKey = "speechLang", tempoKey = "speechTempo"
    static let voiceDeKey = "voiceDe", voiceEnKey = "voiceEn", readFinishedKey = "readFinished"

    private static var d: UserDefaults { .standard }

    /// Recognition locale for the setting auto | de | en.
    static var recognitionLocale: String {
        Voices.recognitionLocale(setting: d.string(forKey: recogKey) ?? "auto", preferred: Locale.preferredLanguages)
    }
    static var tempo: Double {
        let t = d.object(forKey: tempoKey) as? Double ?? 1.0
        return min(max(t, 0.5), 1.5)
    }
    static var readFinished: Bool { d.bool(forKey: readFinishedKey) }

    /// Installed offline voices of a language ("de" or "en"), best first. Novelty and Eloquence voices are left out.
    static func voices(_ lang: String) -> [AVSpeechSynthesisVoice] {
        let home = lang == "de" ? ["de-DE"] : ["en-US", "en-GB"]
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { home.contains($0.language) && !$0.identifier.contains("eloquence") && !$0.identifier.contains("speech.synthesis.voice") }
            .sorted {
                let a = Voices.rank(quality: $0.quality.rawValue, language: $0.language, lang: lang)
                let b = Voices.rank(quality: $1.quality.rawValue, language: $1.language, lang: lang)
                return a != b ? a > b : $0.name < $1.name
            }
    }

    static func label(_ v: AVSpeechSynthesisVoice) -> String {
        let q: String
        switch v.quality { case .premium: q = "premium"; case .enhanced: q = "enhanced"; default: q = "kompakt" }
        return "\(v.name) · \(v.language) · \(q)"
    }

    /// The chosen voice for a language if still installed, else the best one.
    static func voice(lang: String) -> AVSpeechSynthesisVoice? {
        let all = voices(lang)
        let chosen = d.string(forKey: lang == "de" ? voiceDeKey : voiceEnKey) ?? ""
        return all.first { $0.identifier == chosen } ?? all.first ?? AVSpeechSynthesisVoice(language: lang == "de" ? "de-DE" : "en-US")
    }

    static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        voice(lang: Voices.langFor(text, setting: d.string(forKey: langKey) ?? "auto"))
    }
}

struct RelayErrorText: LocalizedError {
    let text: String
    init(_ t: String) { text = t }
    var errorDescription: String? { text }
}

/// The request the audio tap feeds; swapped when a new recognition segment starts. The tap runs on a realtime thread.
final class RequestSink: @unchecked Sendable {
    private let lock = NSLock()
    private var req: SFSpeechAudioBufferRecognitionRequest?
    func set(_ r: SFSpeechAudioBufferRecognitionRequest?) { lock.lock(); req = r; lock.unlock() }
    func append(_ b: AVAudioPCMBuffer) { lock.lock(); let r = req; lock.unlock(); r?.append(b) }
}
