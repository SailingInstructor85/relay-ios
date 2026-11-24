import Foundation
import AVFoundation
import CoreML
import UIKit
import RelayCore

/// Rechnet mit dem geladenen Modell, außerhalb des Hauptthreads und immer nur ein Satz zur Zeit.
actor SupertonicWorker {
    private var model: SupertonicTTSModel?

    var loaded: Bool { model != nil }

    /// Lädt das Modell (beim ersten Mal übersetzt iOS die vier Teile, das dauert).
    func load(_ dir: URL) throws {
        if model == nil { model = try SupertonicTTSModel(directory: dir, computeUnits: .all) }
    }

    func synthesize(_ text: String, dir: URL, speed: Float) throws -> [Float] {
        try load(dir)
        guard let model else { return [] }
        return try model.synthesize(text: text, voice: VoiceModel.voice, language: VoiceModel.language,
                                    options: SupertonicOptions(speed: speed))
    }

    func unload() { model = nil }
}

/// Jarvis' Stimme Supertonic 3 (M2) auf dem iPhone: Modell laden (einmalig von Hugging Face, nur auf Knopfdruck),
/// löschen und Sätze in Ton wandeln. Alles danach läuft auf dem Gerät. Gewählt wird die Stimme in den Einstellungen
/// unter „Stimme Deutsch“. Fehlt das Modell oder scheitert etwas, spricht die Apple-Stimme.
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
    /// Größe der Dateien auf dem Gerät (für die Anzeige).
    @Published private(set) var bytes: Int64 = 0

    private let worker = SupertonicWorker()
    private var download: Task<Void, Never>?
    private var warmTask: Task<Void, Never>?
    private var memoryObserver: NSObjectProtocol?
    /// Nur die ersten Sätze nach dem Start gehen mit ihrer Rechenzeit ins Protokoll (Echtzeitfaktor prüfen).
    private var timed = 0
    private var failures = 0

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
    }

    var installed: Bool { phase == .installed }

    /// Supertonic ist als deutsche Stimme gewählt und das Modell liegt auf dem Gerät.
    var active: Bool { installed && SpeechPrefs.supertonicChosen }

    // MARK: laden und löschen

    func startDownload() {
        guard download == nil, !installed else { return }
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
        let worker = worker
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
            done += f.size
            phase = .downloading(done: done, total: total)
        }
        try Task.checkCancellation()
        let note = try JSONSerialization.data(withJSONObject: ["repo": VoiceModel.repo, "files": files.count, "bytes": total])
        try note.write(to: dir.appendingPathComponent(Self.marker), options: .atomic)
    }

    /// Lädt eine Datei in eine Zwischenablage und meldet die geladenen Bytes.
    private static func fetch(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
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

    /// Lädt das Modell in den Speicher, damit der erste Satz nicht warten muss. Mehrfacher Aufruf schadet nicht.
    func warmUp() {
        guard active, !warm, warmTask == nil else { return }
        warming = true
        let worker = worker, dir = Self.dir
        let started = Date()
        warmTask = Task { [weak self] in
            var failure: String?
            do { try await worker.load(dir) } catch { failure = "\(error)" }
            guard let self else { return }
            self.warmTask = nil
            self.warming = false
            if Task.isCancelled { return }
            if let failure {
                AppLog.shared.log("info", "supertonic", "Modell lädt nicht: \(failure)")
                self.phase = .failed("Das Modell ließ sich nicht starten. Die Apple-Stimme spricht weiter. (\(failure))")
            } else {
                self.warm = true
                AppLog.shared.log("info", "supertonic", String(format: "Modell im Speicher nach %.1f s", Date().timeIntervalSince(started)))
            }
        }
    }

    /// Ein deutscher Satz als Ton (mono, 44,1 kHz). Wirft, wenn das Modell fehlt oder die Berechnung scheitert.
    func synthesize(_ text: String) async throws -> [Float] {
        guard installed else { throw RelayErrorText("Supertonic ist nicht geladen.") }
        let worker = worker, dir = Self.dir
        let speed = VoiceModel.speed(tempo: SpeechPrefs.tempo)
        let spoken = VoiceModel.spoken(text)
        let started = Date()
        let pcm: [Float]
        do {
            pcm = try await worker.synthesize(spoken, dir: dir, speed: speed)
        } catch {
            // Zwei Fehler in Folge: Supertonic ruht, bis das Modell neu geladen oder die App neu gestartet wird.
            failures += 1
            AppLog.shared.log("info", "supertonic", "Satz gescheitert: \(error)")
            if failures >= 2 {
                phase = .failed("Supertonic konnte nicht sprechen. Die Apple-Stimme spricht weiter. (\(error))")
            }
            throw error
        }
        failures = 0
        if !warm { warm = true }
        let took = Date().timeIntervalSince(started)
        let length = Double(pcm.count) / Double(VoiceModel.sampleRate)
        if length > 0, timed < 5 {
            timed += 1
            AppLog.shared.log("info", "supertonic", String(format: "Satz %d Zeichen, %.1f s Ton in %.2f s (Faktor %.2f)", spoken.count, length, took, took / length))
        }
        return pcm
    }

    /// Gibt den Speicher des Modells frei (Speicherwarnung). Der nächste Satz lädt es wieder.
    func release() {
        guard warm, warmTask == nil else { return }
        warm = false
        let worker = worker
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
        // Sicherung: Meldet die Ausgabe das Ende nicht (Wechsel des Audiowegs), geht es trotzdem weiter.
        let guardTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((seconds + 2) * 1_000_000_000))
            if !Task.isCancelled { self?.done(id) }
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiting = (id, c)
            node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.done(id) }
            }
            node.play()
        }
        guardTask.cancel()
    }

    private func done(_ id: Int) {
        guard let w = waiting, w.id == id else { return }
        waiting = nil
        w.c.resume()
    }

    /// Bricht den laufenden Ton ab.
    func stop() {
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
