import Foundation

/// Jarvis' Stimme auf dem Gerät: Supertonic 3, Stimme M2 (Martin, 24.11.2026). Hier steht, welche Dateien die App
/// dafür von Hugging Face lädt und wie sie die Dateiliste liest. Die Liste kommt von einem fremden Server und gilt
/// als nicht vertrauenswürdig: nur erwartete Pfade, keine Pfade nach außen, eine Obergrenze für die Größe.
/// Ein späterer Wechsel des Modells tauscht diese Angaben und die Maschine in der App, sonst nichts.
public enum VoiceModel {
    /// Ablage der für Apple-Geräte umgewandelten Fassung (CoreML), nicht von Supertone selbst veröffentlicht.
    public static let repo = "aufklarer/Supertonic-3-CoreML"
    public static let revision = "main"
    public static let voice = "M2"
    public static let language = "de"
    /// Wert der Einstellung „Stimme Deutsch“, wenn Supertonic gewählt ist (sonst die Kennung einer Apple-Stimme).
    public static let tag = "supertonic3-M2"
    public static let title = "Supertonic 3 (M2)"
    /// Mehr lädt die App nicht (das Modell hat rund 400 MB).
    public static let maxBytes: Int64 = 1_500_000_000
    /// Abtastrate des erzeugten Tons.
    public static let sampleRate = 44100

    static let bundles = ["DurationPredictor.mlpackage/", "TextEncoder.mlpackage/", "VectorEstimator.mlpackage/",
                          "Vocoder.mlpackage/"]
    static let single: Set<String> = ["tts.json", "unicode_indexer.json", "voice_styles/\(voice).json"]

    public struct File: Equatable, Sendable {
        public let path: String
        public let size: Int64
        public init(path: String, size: Int64) { self.path = path; self.size = size }
    }

    /// Adresse der Dateiliste (eine Seite, weitere über den Link-Kopf der Antwort).
    public static var listingURL: URL {
        URL(string: "https://huggingface.co/api/models/\(repo)/tree/\(revision)?recursive=true")!
    }

    /// Adresse einer Datei der Ablage, nil bei einem unzulässigen Pfad.
    public static func fileURL(_ path: String) -> URL? {
        guard safe(path) else { return nil }
        let parts = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }
        return URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/" + parts.joined(separator: "/"))
    }

    /// Ein Pfad darf nur innerhalb des Modellordners landen.
    public static func safe(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Braucht die App diese Datei? Die vier Modellteile, zwei Tabellen und nur die Stimme M2.
    public static func wanted(_ path: String) -> Bool {
        guard safe(path) else { return false }
        return single.contains(path) || bundles.contains { path.hasPrefix($0) }
    }

    /// Die gebrauchten Dateien aus einer Seite der Dateiliste (JSON-Feld mit `type`, `path`, `size`).
    public static func files(listing data: Data) -> [File]? {
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        var out: [File] = []
        for r in rows {
            guard (r["type"] as? String) == "file", let path = r["path"] as? String, wanted(path) else { continue }
            let size = (r["size"] as? NSNumber)?.int64Value ?? (r["size"] as? Int).map(Int64.init) ?? 0
            guard size >= 0 else { continue }
            if !out.contains(where: { $0.path == path }) { out.append(File(path: path, size: size)) }
        }
        return out
    }

    /// Adresse der nächsten Seite aus dem Link-Kopf (`<…>; rel="next"`), nur beim selben Server.
    public static func nextPage(link: String?) -> URL? {
        guard let link else { return nil }
        for part in link.components(separatedBy: ",") where part.contains("rel=\"next\"") {
            guard let a = part.firstIndex(of: "<"), let b = part.firstIndex(of: ">"), a < b,
                  let url = URL(string: String(part[part.index(after: a)..<b])),
                  url.scheme == "https", url.host == "huggingface.co" else { return nil }
            return url
        }
        return nil
    }

    /// Was fehlt, damit das Modell vollständig ist? Leer heißt vollständig. Ohne Stimme oder ohne einen der vier
    /// Modellteile lässt sich nichts sprechen.
    public static func missing(in files: [File]) -> [String] {
        var out = single.sorted().filter { name in !files.contains { $0.path == name } }
        for b in bundles where !files.contains(where: { $0.path.hasPrefix(b) }) { out.append(String(b.dropLast())) }
        return out
    }

    public static func totalBytes(_ files: [File]) -> Int64 { files.reduce(0) { $0 + $1.size } }

    /// „412 MB“ für die Anzeige.
    public static func sizeText(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000).replacingOccurrences(of: ".", with: ",") }
        return "\(Int(mb.rounded())) MB"
    }

    /// Tempo des Modells für die Einstellung „Tempo“ der App (1,0 ist das Tempo der Hörproben).
    public static func speed(tempo: Double) -> Float {
        Float(1.05 * min(max(tempo, 0.5), 1.5))
    }

    /// Der Satz, wie Supertonic ihn bekommt: Wörter der Ausspracheliste in der Schreibweise für die Stimme, Zahlen,
    /// Daten und Uhrzeiten als deutsche Wörter.
    public static func spoken(_ text: String) -> String { SpokenNumbers.german(SpokenWords.respell(text)) }
}

/// Wo Supertonic rechnet. Im Vordergrund nimmt iOS, was am schnellsten ist (auch den Grafikchip). Im Hintergrund
/// (Bildschirm gesperrt, andere App vorn) verbietet iOS Arbeit auf dem Grafikchip, die Berechnung scheitert dann mit
/// „Unable to compute the prediction using ML Program“ (Messung vom 25.11.2026). Dort rechnet nur der Prozessor.
/// Scheitert ein Satz, kommt ein zweiter Versuch auf dem Prozessor mit frisch geladenem Modell, erst danach spricht
/// die Apple-Stimme. Reine Entscheidung, die App lädt das Modell passend.
public struct VoiceCompute: Equatable, Sendable {
    public enum Units: String, Equatable, Sendable {
        /// Alles, was das Gerät hat (Grafikchip, Neural Engine, Prozessor). Nur im Vordergrund erlaubt.
        case all
        /// Nur der Prozessor. Langsamer, geht aber auch im Hintergrund.
        case cpu
    }

    /// So viele Sätze in Folge dürfen ganz scheitern (beide Versuche), dann ruht Supertonic.
    public static let failureLimit = 2

    /// Der Grafikchip hat im Vordergrund versagt: Bis zum Neuladen rechnet nur noch der Prozessor.
    public private(set) var cpuOnly = false
    /// Sätze in Folge, bei denen auch der zweite Versuch gescheitert ist.
    public private(set) var failures = 0

    public init() {}

    /// Womit der nächste Satz gerechnet wird.
    public func units(foreground: Bool) -> Units { cpuOnly || !foreground ? .cpu : .all }

    /// Die Fehlermeldung von iOS, wenn die App im Hintergrund auf den Grafikchip wollte.
    public static func backgroundDenied(_ error: String) -> Bool {
        let e = error.lowercased()
        return e.contains("backgroundexecutionnotpermitted") || e.contains("gpu work from background")
    }

    /// Ein Satz ist gesprochen. `firstError`: Der erste Versuch war gescheitert, erst der zweite auf dem Prozessor
    /// hat geklappt. Lag das nicht am Hintergrund, bleibt es beim Prozessor (sonst scheiterte jeder Satz erst einmal).
    public mutating func succeeded(with units: Units, firstError: String?) {
        failures = 0
        if let firstError, units == .all, !Self.backgroundDenied(firstError) { cpuOnly = true }
    }

    /// Beide Versuche sind gescheitert. true: Supertonic soll ruhen, die Apple-Stimme spricht weiter.
    public mutating func failed() -> Bool {
        failures += 1
        return failures >= Self.failureLimit
    }

    /// Das Modell wird neu geladen: alles wieder wie am Anfang.
    public mutating func reset() { self = VoiceCompute() }

    /// Kurzer Text fürs Protokoll (Fehlermeldungen von iOS sind sehr lang).
    public static func brief(_ error: String, limit: Int = 300) -> String {
        let one = error.split(whereSeparator: \.isNewline).joined(separator: " ")
        return one.count > limit ? String(one.prefix(limit)) + "…" : one
    }
}
