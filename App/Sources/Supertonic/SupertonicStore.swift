import Foundation
import AVFoundation
import CoreML
import UIKit
import RelayCore

/// Rechnet mit dem geladenen Modell, außerhalb des Hauptthreads und immer nur ein Satz zur Zeit.
actor SupertonicWorker {
    /// Ton eines Satzes. `units`: womit der erste Versuch gerechnet hat. `firstError`: Der erste Versuch ist
    /// gescheitert, der Ton stammt vom zweiten (Prozessor).
    struct Spoken: Sendable {
        let pcm: [Float]
        let units: VoiceCompute.Units
        let firstError: String?
    }

    private var model: SupertonicTTSModel?
    private var loaded: VoiceCompute.Units?
    private var primed = false
    /// Die App ist im Hintergrund: Dort rechnet nur der Prozessor. Entschieden wird erst, wenn ein Satz an der Reihe
    /// ist, nicht wenn er eingereiht wird. Vorausberechnete Sätze einer Antwort warten hier, und sperrt sich das
    /// iPhone inzwischen, sollen sie nicht erst auf dem Grafikchip scheitern.
    private var background = false

    func setBackground(_ on: Bool) { background = on }

    private func units(cpuOnly: Bool) -> VoiceCompute.Units { cpuOnly || background ? .cpu : .all }

    /// Lädt das Modell (beim ersten Mal übersetzt iOS die vier Teile, das dauert). Liegt es schon für einen anderen
    /// Rechenweg im Speicher, wird es für den verlangten neu geladen.
    private func load(_ dir: URL, units wanted: VoiceCompute.Units) throws {
        if model != nil, loaded == wanted { return }
        unload()
        model = try SupertonicTTSModel(directory: dir, computeUnits: wanted == .cpu ? .cpuOnly : .all)
        loaded = wanted
    }

    /// Lädt das Modell und rechnet einmal einen kurzen Satz, ohne ihn abzuspielen. Der erste Satz nach dem Laden
    /// braucht ein Vielfaches (gemessen 7,35 s für 37 Zeichen, danach 0,5 s), weil iOS die Rechenwege erst dann
    /// einrichtet. So fällt diese Wartezeit nicht auf den ersten Satz einer Antwort. Scheitert das Aufwärmen, zeigt
    /// sich der Fehler beim ersten echten Satz, dort mit zweitem Versuch. `foreground`: Stand der App beim Aufruf.
    /// `fresh`: ein Modell im Speicher vorher verwerfen (neuer Anlauf nach Fehlern).
    func warm(_ dir: URL, cpuOnly: Bool, foreground: Bool, fresh: Bool = false) throws {
        background = !foreground
        if fresh { unload() }
        try load(dir, units: units(cpuOnly: cpuOnly))
        guard !primed, let model else { return }
        primed = true
        _ = try? model.synthesize(text: "Hallo.", voice: VoiceModel.voice, language: VoiceModel.language,
                                  options: SupertonicOptions())
    }

    /// Scheitert der Satz, kommt ein zweiter Versuch auf dem Prozessor mit frisch geladenem Modell. Das hilft, wenn
    /// iOS den Grafikchip verweigert, weil die App inzwischen im Hintergrund ist. Wirft erst, wenn auch der scheitert.
    /// Ein abgebrochener Satz (Vorlesen gestoppt) wird gar nicht erst gerechnet.
    func synthesize(_ text: String, dir: URL, speed: Float, cpuOnly: Bool) throws -> Spoken {
        try Task.checkCancellation()
        let wanted = units(cpuOnly: cpuOnly)
        do {
            return Spoken(pcm: try run(text, dir: dir, speed: speed, units: wanted), units: wanted, firstError: nil)
        } catch {
            let first = "\(error)"
            // iOS hat den Grafikchip verweigert: Die App ist im Hintergrund, auch wenn es hier noch nicht angekommen ist.
            if VoiceCompute.backgroundDenied(first) { background = true }
            unload()
            return Spoken(pcm: try run(text, dir: dir, speed: speed, units: .cpu), units: wanted, firstError: first)
        }
    }

    /// Wie `synthesize`, dazu der Zeitpunkt, an dem die Berechnung begonnen hat (nicht der des Einreihens).
    struct Timed: Sendable {
        let spoken: Spoken
        let started: Date
    }

    func timedSynthesize(_ text: String, dir: URL, speed: Float, cpuOnly: Bool) throws -> Timed {
        let started = Date()
        return Timed(spoken: try synthesize(text, dir: dir, speed: speed, cpuOnly: cpuOnly), started: started)
    }

    private func run(_ text: String, dir: URL, speed: Float, units wanted: VoiceCompute.Units) throws -> [Float] {
        try load(dir, units: wanted)
        guard let model else { return [] }
        return try model.synthesize(text: text, voice: VoiceModel.voice, language: VoiceModel.language,
                                    options: SupertonicOptions(speed: speed))
    }

    func unload() { model = nil; loaded = nil; primed = false }
}

/// Jarvis' Stimme Supertonic 3 (M2) auf dem iPhone: Modell laden (einmalig von Hugging Face, nur auf Knopfdruck),
/// löschen und Sätze in Ton wandeln. Alles danach läuft auf dem Gerät. Gewählt wird die Stimme in den Einstellungen
/// unter „Stimme Deutsch“. Fehlt das Modell oder scheitert etwas, spricht die Apple-Stimme. Dauerhaft abgeschaltet
/// wird Supertonic nicht: Nach Fehlern beginnt die nächste Antwort mit frisch geladenem Modell (`wake`).
@MainActor
final class SupertonicStore: ObservableObject {
    static let shared = SupertonicStore()

    enum Phase: Equatable {
        case missing
        case downloading(done: Int64, total: Int64)
        case installed
        case failed(String)
    }

    @Published private(set) var phase: Phase
    /// Das Modell ist im Speicher und kann sofort sprechen.
    @Published private(set) var warm = false
    @Published private(set) var warming = false
    /// Zwei Sätze in Folge sind ganz gescheitert: Den Rest der Antwort spricht die Apple-Stimme. Die nächste Antwort
    /// oder die Rückkehr in den Vordergrund beendet die Ruhe (`wake`).
    @Published private(set) var resting = false
    /// Größe der Dateien auf dem Gerät (für die Anzeige).
    @Published private(set) var bytes: Int64 = 0

    private let worker = SupertonicWorker()
    private var download: Task<Void, Never>?
    private var warmTask: Task<Void, Never>?
    private var memoryObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    /// Nur die ersten Sätze nach dem Start gehen mit ihrer Rechenzeit ins Protokoll (Echtzeitfaktor prüfen), getrennt
    /// gezählt für den schnellen Weg und den Prozessor (der rechnet meist erst später, im Hintergrund).
    private var timed = 0
    private var timedProcessor = 0
    /// `phase == .failed`, weil das Modell nicht starten wollte. Die Dateien liegen da, ein neuer Anlauf lohnt sich.
    private var startFailed = false
    /// Rechenweg (Grafikchip oder nur Prozessor) und Fehler in Folge, siehe `VoiceCompute`.
    private var compute = VoiceCompute()
    /// Der zweite Versuch auf dem Prozessor steht nur einmal je App-Start im Protokoll.
    private var retryLogged = false

    private static let marker = "relay-vollstaendig.json"

    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("supertonic3", isDirectory: true)
    }

    private init() {
        let marker = Self.dir.appendingPathComponent(Self.marker)
        phase = FileManager.default.fileExists(atPath: marker.path) ? .installed : .missing
        if phase == .installed { bytes = Self.storedBytes() }
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.release() }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cameToFront() }
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.wentToBackground() }
        }
    }

    var installed: Bool { phase == .installed }

    /// Supertonic ist als deutsche Stimme gewählt, das Modell liegt auf dem Gerät und ruht nicht nach Fehlern.
    var active: Bool { installed && SpeechPrefs.supertonicChosen && !resting }

    /// Warum gerade die Apple-Stimme spricht, obwohl Supertonic gewählt und geladen ist. nil: nicht gewählt, Modell
    /// fehlt oder lädt noch (das ist kein Rückfall), oder Supertonic ist bereit.
    var idleReason: String? {
        guard SpeechPrefs.supertonicChosen else { return nil }
        if resting { return "Supertonic ruht nach \(VoiceCompute.failureLimit) gescheiterten Sätzen bis zur nächsten Antwort" }
        if startFailed, case .failed(let why) = phase { return why }
        return nil
    }

    // MARK: laden und löschen

    func startDownload() {
        guard download == nil, !installed else { return }
        startFailed = false
        phase = .downloading(done: 0, total: 0)
        download = Task { [weak self] in
            let result: Phase
            do {
                try await self?.fetchAll()
                result = .installed
            } catch is CancellationError {
                result = .missing
            } catch {
                result = (error as? URLError)?.code == .cancelled ? .missing : .failed(Self.text(error))
            }
            guard let self else { return }
            self.download = nil
            self.phase = result
            if result == .installed {
                self.compute.reset()
                self.resting = false
                self.bytes = Self.storedBytes()
                AppLog.shared.log("info", "supertonic", "geladen, \(VoiceModel.sizeText(self.bytes))")
                self.warmUp()
            } else if case .failed(let why) = result {
                AppLog.shared.log("info", "supertonic", "Laden gescheitert: \(why)")
            }
        }
    }

    func cancelDownload() {
        download?.cancel()
    }

    func delete() {
        download?.cancel()
        warmTask?.cancel()
        warm = false
        warming = false
        compute.reset()
        resting = false
        startFailed = false
        let worker = self.worker
        Task { await worker.unload() }
        try? FileManager.default.removeItem(at: Self.dir)
        bytes = 0
        phase = .missing
        if SpeechPrefs.supertonicChosen { UserDefaults.standard.set("", forKey: SpeechPrefs.voiceDeKey) }
    }

    private func fetchAll() async throws {
        let fm = FileManager.default
        var dir = Self.dir
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        try? fm.removeItem(at: dir.appendingPathComponent(Self.marker))

        // Dateiliste, höchstens 20 Seiten
        var files: [VoiceModel.File] = []
        var next: URL? = VoiceModel.listingURL
        var pages = 0
        while let url = next, pages < 20 {
            pages += 1
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw RelayErrorText("Die Dateiliste des Modells ließ sich nicht abrufen.")
            }
            guard let page = VoiceModel.files(listing: data) else {
                throw RelayErrorText("Die Dateiliste des Modells ist nicht lesbar.")
            }
            for f in page where !files.contains(where: { $0.path == f.path }) { files.append(f) }
            next = VoiceModel.nextPage(link: http.value(forHTTPHeaderField: "Link"))
        }
        let missing = VoiceModel.missing(in: files)
        guard missing.isEmpty else {
            throw RelayErrorText("Im Modell fehlt: \(missing.joined(separator: ", ")).")
        }
        let total = VoiceModel.totalBytes(files)
        guard total <= VoiceModel.maxBytes else {
            throw RelayErrorText("Das Modell ist mit \(VoiceModel.sizeText(total)) größer als erwartet. Nichts geladen.")
        }
        phase = .downloading(done: 0, total: total)

        var done: Int64 = 0
        for f in files {
            try Task.checkCancellation()
            guard let url = VoiceModel.fileURL(f.path) else { continue }
            let dest = dir.appendingPathComponent(f.path)
            // schon vollständig da (abgebrochener Versuch): nicht noch einmal laden
            if f.size > 0, let have = (try? fm.attributesOfItem(atPath: dest.path))?[.size] as? NSNumber, have.int64Value == f.size {
                done += f.size
                phase = .downloading(done: done, total: total)
                continue
            }
            let base = done
            let tmp = try await Self.fetch(url) { [weak self] part in
                Task { @MainActor in
                    guard let self, case .downloading = self.phase else { return }
                    self.phase = .downloading(done: base + min(part, f.size), total: total)
                }
            }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: tmp, to: dest)
            // Stimmt die Größe nicht mit der Dateiliste überein, kam etwas anderes als die Datei (Fehlerseite, Abbruch).
            if f.size > 0, let got = (try? fm.attributesOfItem(atPath: dest.path))?[.size] as? NSNumber, got.int64Value != f.size {
                try? fm.removeItem(at: dest)
                throw RelayErrorText("Eine Datei des Modells kam unvollständig an. Bitte noch einmal laden.")
            }
            done += f.size
            phase = .downloading(done: done, total: total)
        }
        try Task.checkCancellation()
        let note = try JSONSerialization.data(withJSONObject: ["repo": VoiceModel.repo, "files": files.count, "bytes": total])
        try note.write(to: dir.appendingPathComponent(Self.marker), options: .atomic)
    }

    /// Lädt eine Datei in eine Zwischenablage und meldet die geladenen Bytes. Außerhalb des Hauptthreads gebaut:
    /// Die Rückrufe der Übertragung laufen auf fremden Threads.
    nonisolated private static func fetch(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
                var req = URLRequest(url: url, timeoutInterval: 120)
                req.allowsCellularAccess = true
                let task = URLSession.shared.downloadTask(with: req) { tmp, response, error in
                    box.observation?.invalidate()
                    if let error {
                        c.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
                        return
                    }
                    guard let tmp, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        c.resume(throwing: RelayErrorText("Der Server hat eine Datei des Modells nicht geliefert."))
                        return
                    }
                    // die Datei verschwindet nach dieser Rückmeldung: gleich an einen eigenen Platz legen
                    let keep = FileManager.default.temporaryDirectory.appendingPathComponent("supertonic-" + UUID().uuidString)
                    do {
                        try FileManager.default.moveItem(at: tmp, to: keep)
                        c.resume(returning: keep)
                    } catch {
                        c.resume(throwing: error)
                    }
                }
                box.observation = task.progress.observe(\.completedUnitCount) { p, _ in progress(p.completedUnitCount) }
                box.task = task
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    private static func storedBytes() -> Int64 {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var sum: Int64 = 0
        for case let url as URL in e {
            sum += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return sum
    }

    private static func text(_ error: Error) -> String {
        if let e = error as? RelayErrorText { return e.text }
        if let e = error as? URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return "Kein Netz. Bitte später noch einmal laden."
            case .timedOut: return "Der Server hat nicht geantwortet. Bitte später noch einmal laden."
            default: break
            }
        }
        return error.localizedDescription
    }

    // MARK: sprechen

    /// Gleich wird gesprochen (eine Aufnahme beginnt, eine Antwort beginnt): Hat Supertonic nach Fehlern geruht oder
    /// wollte das Modell nicht starten, fängt es jetzt mit frisch geladenem Modell von vorn an. Sonst lädt das Modell
    /// in den Speicher, falls es dort noch nicht ist. Mehrfacher Aufruf schadet nicht.
    func wake() {
        let fresh = revive()
        warmUp(fresh: fresh)
    }

    /// Beendet die Ruhe nach Fehlern. true: Das Modell soll frisch geladen werden.
    private func revive() -> Bool {
        guard download == nil, warmTask == nil else { return false }
        var again = compute.revive()
        if startFailed, case .failed = phase {
            // Die Dateien liegen da, nur der Start ist gescheitert: noch ein Versuch. Scheitert er wieder, steht der
            // Fehler wieder in der Stimmenauswahl.
            startFailed = false
            compute.reset()
            phase = .installed
            again = true
        }
        guard again else { return false }
        resting = false
        warm = false
        AppLog.shared.log("info", "supertonic", "Neuer Anlauf nach Fehlern, das Modell wird frisch geladen", keep: true)
        return true
    }

    /// Lädt das Modell in den Speicher, damit der erste Satz nicht warten muss. Mehrfacher Aufruf schadet nicht.
    /// `fresh`: ein Modell im Speicher vorher verwerfen.
    func warmUp(fresh: Bool = false) {
        guard active, !warm, warmTask == nil else { return }
        warming = true
        let worker = self.worker, dir = Self.dir
        let cpuOnly = compute.cpuOnly, foreground = Self.foreground
        let started = Date()
        warmTask = Task { [weak self] in
            var failure: String?
            do { try await worker.warm(dir, cpuOnly: cpuOnly, foreground: foreground, fresh: fresh) } catch { failure = "\(error)" }
            guard let self else { return }
            self.warmTask = nil
            self.warming = false
            if Task.isCancelled { return }
            if let failure {
                AppLog.shared.log("info", "supertonic", "Modell lädt nicht: " + VoiceCompute.brief(failure), keep: true)
                // Erst jetzt steht der Fehler in der Stimmenauswahl. Die nächste Antwort versucht es trotzdem wieder.
                self.startFailed = true
                self.phase = .failed("Das Modell ließ sich nicht starten. Die Apple-Stimme spricht, bei der nächsten Antwort versucht Relay es wieder. (" + VoiceCompute.brief(failure, limit: 160) + ")")
            } else {
                self.warm = true
                AppLog.shared.log("info", "supertonic", String(format: "Modell im Speicher und aufgewärmt nach %.1f s", Date().timeIntervalSince(started)))
            }
        }
    }

    /// Ein deutscher Satz als Ton (mono, 44,1 kHz). Wirft, wenn das Modell fehlt, Supertonic nach Fehlern ruht, die
    /// Berechnung scheitert oder der Aufrufer abgebrochen hat.
    func synthesize(_ text: String) async throws -> [Float] {
        guard installed else { throw RelayErrorText("Supertonic ist nicht geladen.") }
        guard !resting else { throw RelayErrorText("Supertonic ruht nach Fehlern bis zur nächsten Antwort.") }
        let worker = self.worker, dir = Self.dir
        let speed = VoiceModel.speed(tempo: SpeechPrefs.tempo)
        let spoken = VoiceModel.spoken(text)
        let cpuOnly = compute.cpuOnly
        let answer: SupertonicWorker.Timed
        do {
            // Die Uhr läuft erst, wenn der Satz an der Reihe ist: Vorausberechnete Sätze warten in der Schlange.
            answer = try await worker.timedSynthesize(spoken, dir: dir, speed: speed, cpuOnly: cpuOnly)
        } catch is CancellationError {
            throw CancellationError()  // Vorlesen gestoppt: kein Fehler des Modells
        } catch {
            // Auch der zweite Versuch auf dem Prozessor ist gescheitert. Nach zwei solchen Sätzen in Folge ruht
            // Supertonic für den Rest der Antwort; die nächste Antwort lädt das Modell frisch (`wake`).
            warm = false
            let why = "\(error)"
            AppLog.shared.log("info", "supertonic", "Satz gescheitert, auch beim zweiten Versuch: " + VoiceCompute.brief(why), keep: true)
            if compute.failed(), !resting {
                resting = true
                AppLog.shared.log("info", "supertonic", "Supertonic ruht bis zur nächsten Antwort, so lange spricht die Apple-Stimme", keep: true)
            }
            throw error
        }
        let result = answer.spoken, started = answer.started
        let pcm = result.pcm
        compute.succeeded(with: result.units, firstError: result.firstError)
        if let first = result.firstError, !retryLogged {
            retryLogged = true
            let place = Self.foreground ? "vorn" : "im Hintergrund"
            AppLog.shared.log("info", "supertonic", "Satz beim zweiten Versuch auf dem Prozessor gesprochen (App \(place)). Erster Fehler: " + VoiceCompute.brief(first), keep: true)
        }
        if !warm, !resting { warm = true }
        let took = Date().timeIntervalSince(started)
        let length = Double(pcm.count) / Double(VoiceModel.sampleRate)
        let processor = result.firstError != nil || result.units == .cpu
        // Die ersten Sätze je Rechenweg: So steht auch der Echtzeitfaktor des Prozessors im Protokoll, der meist erst
        // im Hintergrund rechnet. Beim zweiten Versuch steckt das Neuladen des Modells in der Zeit.
        if length > 0, (processor ? timedProcessor : timed) < 5 {
            if processor { timedProcessor += 1 } else { timed += 1 }
            let how = VoiceCompute.timingNote(processor: processor, foreground: Self.foreground)
                + (result.firstError != nil ? ", mit Neuladen" : "")
            AppLog.shared.log("info", "supertonic", String(format: "Satz %d Zeichen, %.1f s Ton in %.2f s (Faktor %.2f)", spoken.count, length, took, took / length) + how, keep: processor)
        }
        return pcm
    }

    /// Die App ist nicht im Hintergrund. Dort verbietet iOS Arbeit auf dem Grafikchip, es rechnet nur der Prozessor.
    private static var foreground: Bool { UIApplication.shared.applicationState != .background }

    /// Die App ist wieder vorn. Hat Supertonic nach Fehlern geruht, beginnt es von vorn. Hat das Modell im Hintergrund
    /// auf dem Prozessor gerechnet, lädt es jetzt schon für den schnellen Weg, damit der nächste Satz nicht darauf
    /// warten muss.
    private func cameToFront() {
        let worker = self.worker, dir = Self.dir
        if revive() {
            Task { await worker.setBackground(false) }
            warmUp(fresh: true)
            return
        }
        let reload = active && warm && warmTask == nil
        let cpuOnly = compute.cpuOnly
        Task {
            await worker.setBackground(false)
            if reload { try? await worker.warm(dir, cpuOnly: cpuOnly, foreground: true) }
        }
    }

    /// Die App geht in den Hintergrund: Ab dem nächsten Satz rechnet nur noch der Prozessor.
    private func wentToBackground() {
        let worker = self.worker
        Task { await worker.setBackground(true) }
    }

    /// Gibt den Speicher des Modells frei (Speicherwarnung). Der nächste Satz lädt es wieder.
    func release() {
        guard warm, warmTask == nil else { return }
        warm = false
        let worker = self.worker
        Task { await worker.unload() }
    }
}

/// Hält die laufende Übertragung fest, damit ein Abbruch sie erreicht.
private final class TaskBox: @unchecked Sendable {
    var task: URLSessionDownloadTask?
    var observation: NSKeyValueObservation?
}

/// Spielt erzeugten Ton ab (mono, 44,1 kHz) und meldet, wenn er zu Ende ist.
@MainActor
final class PCMPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Double(VoiceModel.sampleRate), channels: 1)
    private var wired = false
    private var waiting: (id: Int, c: CheckedContinuation<Void, Never>)?
    private var serial = 0
    /// Der laufende Ton ist angehalten (`pause`), bis `resume` oder `stop`.
    private(set) var held = false

    /// Spielt den Ton und kehrt zurück, wenn er zu Ende ist oder `stop()` ihn abbricht.
    func play(_ pcm: [Float]) async throws {
        guard !pcm.isEmpty else { return }
        guard let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw RelayErrorText("Ton lässt sich nicht abspielen.")
        }
        pcm.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { channel.update(from: base, count: pcm.count) }
        }
        buffer.frameLength = AVAudioFrameCount(pcm.count)
        if !wired {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            wired = true
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        serial += 1
        let id = serial
        let seconds = Double(pcm.count) / format.sampleRate
        held = false
        // Sicherung: Meldet die Ausgabe das Ende nicht (Wechsel des Audiowegs), geht es trotzdem weiter. Die Zeit
        // einer Pause zählt nicht mit.
        let guardTask = Task { [weak self] in
            var left = seconds + 2
            while left > 0 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                if self?.held != true { left -= 0.25 }
            }
            self?.done(id)
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiting = (id, c)
            Self.schedule(buffer, on: node) { [weak self] in
                Task { @MainActor in self?.done(id) }
            }
            node.play()
        }
        guardTask.cancel()
    }

    /// Außerhalb des Hauptthreads gebaut: Die Rückmeldung der Ausgabe kommt auf einem Audiothread.
    nonisolated private static func schedule(_ buffer: AVAudioPCMBuffer, on node: AVAudioPlayerNode,
                                             done: @escaping @Sendable () -> Void) {
        node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in done() }
    }

    private func done(_ id: Int) {
        guard let w = waiting, w.id == id else { return }
        waiting = nil
        w.c.resume()
    }

    /// Hält den laufenden Ton an. false: Es läuft gerade keiner.
    @discardableResult
    func pause() -> Bool {
        guard wired, engine.isRunning, waiting != nil, !held else { return false }
        node.pause()
        held = true
        return true
    }

    /// Spielt nach `pause` an derselben Stelle weiter.
    func resume() {
        guard held else { return }
        held = false
        if !engine.isRunning { try? engine.start() }
        node.play()
    }

    /// Bricht den laufenden Ton ab.
    func stop() {
        held = false
        if wired, engine.isRunning { node.stop() }
        if let w = waiting {
            waiting = nil
            w.c.resume()
        }
    }

    /// Nichts mehr zu spielen: die Ausgabe ruht, bis der nächste Satz kommt.
    func rest() {
        guard wired, engine.isRunning, waiting == nil else { return }
        node.stop()
        engine.stop()
    }
}
