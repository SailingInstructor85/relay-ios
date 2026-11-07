import Foundation

// Telefonzugriff, Stufe 1 (docs/telefonzugriff.md): Agenten lesen über das Gateway Geräteinfos, freigegebene Ordner,
// Fotos und die Zwischenablage. Lesen läuft ohne Einzelbestätigung, aber nur in Bereichen, die Martin einmal
// eingeschaltet hat, und immer mit Protokoll. Der Not-Aus lehnt alles ab. Hier liegt die reine Logik; die App führt aus.

/// Bereiche mit eigenem Schalter.
public enum PhoneArea: String, CaseIterable, Sendable, Codable {
    case device, files, photos, clipboard

    public var title: String {
        switch self {
        case .device: return "Geräteinfos"
        case .files: return "Ordner"
        case .photos: return "Fotos"
        case .clipboard: return "Zwischenablage"
        }
    }

    public var help: String {
        switch self {
        case .device: return "Akku, freier Speicher, iOS-Version, Gerätemodell, Netz"
        case .files: return "Dateien in den Ordnern, die du unten freigibst (auch Google Drive über die Dateien-App)"
        case .photos: return "Liste der neuesten Fotos und einzelne Fotos, verkleinert"
        case .clipboard: return "Text der Zwischenablage, nur bei geöffneter App, iOS fragt jedes Mal"
        }
    }
}

/// Fehlerwörter laut Protokoll (`phone_command_result.error`).
public enum PhoneCmdError: String, Sendable, Equatable {
    case denied, unsupported, killswitch, expired, failed
    case notAllowed = "not_allowed"
    case notInForeground = "not_in_foreground"
    case rateLimit = "rate_limit"
}

/// Ein Befehl vom Gateway (Ereignis `phone_command` oder `phone_command_pending`).
public struct PhoneCommand: Sendable, Equatable {
    public let id: String
    public let name: String
    public let args: [String: JSON]
    public let requestedBy: String
    public let reason: String
    public let expiresAt: Double

    public init(id: String, name: String, args: [String: JSON] = [:], requestedBy: String = "", reason: String = "", expiresAt: Double = 0) {
        self.id = id; self.name = name; self.args = args; self.requestedBy = requestedBy; self.reason = reason; self.expiresAt = expiresAt
    }

    public static func from(_ j: JSON) -> PhoneCommand? {
        let id = j.str("request_id"), name = j.str("command")
        guard !id.isEmpty, !name.isEmpty else { return nil }
        return PhoneCommand(id: id, name: name, args: j["args"].object ?? [:], requestedBy: j.str("requested_by", "ein Agent"),
                            reason: j.str("reason"), expiresAt: j.num("expires_at"))
    }

    public func string(_ key: String) -> String { (args[key]?.string ?? "").trimmingCharacters(in: .whitespaces) }
    public func int(_ key: String) -> Int? { args[key]?.int }
}

/// Der feste Katalog der Stufe 1. Unbekannte Befehle lehnt die App ab, auch wenn das Gateway sie schicken würde.
public enum PhoneCatalog {
    public struct Spec: Sendable {
        public let area: PhoneArea
        public let required: [String]
        public let optional: [String]
        public let foreground: Bool
        public let title: String
    }

    public static let specs: [String: Spec] = [
        "device_info": Spec(area: .device, required: [], optional: [], foreground: false, title: "Geräteinfos"),
        "files_list": Spec(area: .files, required: ["folder"], optional: ["path"], foreground: false, title: "Ordner auflisten"),
        "files_get": Spec(area: .files, required: ["folder", "path"], optional: [], foreground: false, title: "Datei holen"),
        "photos_recent": Spec(area: .photos, required: [], optional: ["count", "since"], foreground: false, title: "Neueste Fotos"),
        "photos_get": Spec(area: .photos, required: ["id"], optional: ["max_px"], foreground: false, title: "Foto holen"),
        "clipboard_get": Spec(area: .clipboard, required: [], optional: [], foreground: true, title: "Zwischenablage lesen"),
    ]

    public static let maxFileBytes = 50 * 1024 * 1024
    public static let maxPhotos = 20
    public static let ratePerHour = 30

    public static func title(_ name: String) -> String { specs[name]?.title ?? name }

    /// nil: Befehl und Felder passen zum Katalog.
    public static func validate(_ c: PhoneCommand) -> PhoneCmdError? {
        guard let s = specs[c.name] else { return .unsupported }
        if Set(c.args.keys).subtracting(s.required + s.optional).count > 0 { return .unsupported }
        for r in s.required where c.string(r).isEmpty { return .unsupported }
        return nil
    }

    /// Anzahl Fotos: 1 bis 20, ohne Angabe 10.
    public static func photoCount(_ c: PhoneCommand) -> Int { min(max(c.int("count") ?? 10, 1), maxPhotos) }
    /// Längste Kante beim Foto: 256 bis 4096, ohne Angabe 2048 (wie Anhänge).
    public static func maxPx(_ c: PhoneCommand) -> Int { min(max(c.int("max_px") ?? 2048, 256), 4096) }
}

/// Martins Schalter in „Telefonzugriff“.
public struct PhoneSettings: Sendable, Equatable {
    public var killswitch: Bool
    public var areas: Set<PhoneArea>
    public var folders: [String]

    public init(killswitch: Bool = false, areas: Set<PhoneArea> = [], folders: [String] = []) {
        self.killswitch = killswitch; self.areas = areas; self.folders = folders
    }

    /// Nutzlast für `phone_caps`.
    public var caps: JSON {
        .object(["killswitch": .bool(killswitch),
                 "areas": .array(PhoneArea.allCases.filter { areas.contains($0) }.map { JSON.string($0.rawValue) }),
                 "folders": .array(folders.map { JSON.string($0) })])
    }
}

/// Pfade innerhalb eines freigegebenen Ordners.
public enum PhonePaths {
    /// Bestandteile eines relativen Pfads; nil, wenn er den Ordner verlassen würde (führendes „/“, „..“, „~“).
    public static func components(_ path: String) -> [String]? {
        let p = path.trimmingCharacters(in: .whitespaces)
        if p.hasPrefix("/") || p.hasPrefix("~") { return nil }
        let parts = p.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
        if parts.contains("..") { return nil }
        return parts
    }
}

/// Kurze Namen für freigegebene Ordner („Google Drive/Bewerbungen“ → „bewerbungen“), eindeutig.
public enum FolderNames {
    public static func make(_ display: String, existing: [String]) -> String {
        let map: [Character: String] = ["ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss"]
        var out = ""
        for ch in display.lowercased() {
            if let r = map[ch] { out += r }
            else if ch.isASCII, ch.isLetter || ch.isNumber { out.append(ch) }
            else if !out.hasSuffix("-") { out += "-" }
        }
        var base = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.isEmpty { base = "ordner" }
        if base.count > 40 { base = String(base.prefix(40)) }
        var name = base, n = 2
        while existing.contains(name) { name = "\(base)-\(n)"; n += 1 }
        return name
    }
}

/// Ein Eintrag im Verlauf (ohne Inhalte).
public struct PhoneLogEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ts: Double
    public var command: String
    public var requestedBy: String
    public var reason: String
    public var outcome: String   // "done" oder ein Fehlerwort
    public var detail: String    // „12 Einträge“, „Datei, 1,2 MB“; nie Inhalte
    public var durationMs: Int

    public init(id: String, ts: Double, command: String, requestedBy: String, reason: String, outcome: String, detail: String = "", durationMs: Int = 0) {
        self.id = id; self.ts = ts; self.command = command; self.requestedBy = requestedBy; self.reason = reason
        self.outcome = outcome; self.detail = detail; self.durationMs = durationMs
    }

    public var ok: Bool { outcome == "done" }
}

public enum PhoneLog {
    public static let keepDays = 30.0
    public static let maxEntries = 1000

    /// Neuester Eintrag zuerst; älter als 30 Tage fällt weg, höchstens 1000; derselbe Befehl nur einmal.
    public static func add(_ e: PhoneLogEntry, to list: [PhoneLogEntry], now: Double) -> [PhoneLogEntry] {
        let keep = list.filter { $0.id != e.id && $0.ts >= now - keepDays * 86400 }
        return Array(([e] + keep).prefix(maxEntries))
    }

    /// Befehle eines Agenten in der letzten Stunde (Grenze 30).
    public static func recentCount(_ list: [PhoneLogEntry], by requester: String, now: Double) -> Int {
        list.filter { $0.requestedBy == requester && $0.ts >= now - 3600 }.count
    }

    public static func outcomeText(_ outcome: String) -> String {
        switch outcome {
        case "done": return "erledigt"
        case PhoneCmdError.killswitch.rawValue: return "abgelehnt: Not-Aus ist an"
        case PhoneCmdError.notAllowed.rawValue: return "abgelehnt: Bereich oder Ordner nicht freigegeben"
        case PhoneCmdError.unsupported.rawValue: return "abgelehnt: unbekannter Befehl"
        case PhoneCmdError.expired.rawValue: return "abgelaufen"
        case PhoneCmdError.rateLimit.rawValue: return "abgelehnt: mehr als 30 je Stunde"
        case PhoneCmdError.notInForeground.rawValue: return "nicht ausgeführt: Relay war nicht geöffnet"
        case PhoneCmdError.denied.rawValue: return "abgelehnt"
        default: return "fehlgeschlagen"
        }
    }

    /// „1,2 MB“
    public static func size(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb).replacingOccurrences(of: ".", with: ",")
    }
}

/// Entscheidung vor dem Ausführen.
public enum PhonePolicy {
    public enum Decision: Equatable, Sendable {
        case run
        case waitForForeground
        case refuse(PhoneCmdError)
    }

    public static func decide(_ c: PhoneCommand, settings: PhoneSettings, foreground: Bool, now: Double,
                              log: [PhoneLogEntry]) -> Decision {
        if c.expiresAt > 0, now > c.expiresAt { return .refuse(.expired) }
        if settings.killswitch { return .refuse(.killswitch) }
        if let e = PhoneCatalog.validate(c) { return .refuse(e) }
        guard let spec = PhoneCatalog.specs[c.name] else { return .refuse(.unsupported) }
        if !settings.areas.contains(spec.area) { return .refuse(.notAllowed) }
        if spec.area == .files {
            if !settings.folders.contains(c.string("folder")) { return .refuse(.notAllowed) }
            if PhonePaths.components(c.string("path")) == nil { return .refuse(.notAllowed) }
        }
        if PhoneLog.recentCount(log, by: c.requestedBy, now: now) >= PhoneCatalog.ratePerHour { return .refuse(.rateLimit) }
        if spec.foreground && !foreground { return .waitForForeground }
        return .run
    }
}

/// Ergebnis von `device_info`.
public enum DeviceInfo {
    public static func json(battery: Float, charging: Bool?, freeBytes: Int64?, totalBytes: Int64?, ios: String,
                            model: String, app: String, network: String) -> JSON {
        var o: [String: JSON] = ["ios": .string(ios), "model": .string(model), "relay": .string(app), "network": .string(network),
                                 "focus": .string("nicht lesbar")]
        if battery >= 0 { o["battery_percent"] = .number(Double(Int((battery * 100).rounded()))) }
        if let c = charging { o["charging"] = .bool(c) }
        if let f = freeBytes { o["free_gb"] = .number((Double(f) / 1_000_000_000 * 10).rounded() / 10) }
        if let t = totalBytes { o["total_gb"] = .number((Double(t) / 1_000_000_000 * 10).rounded() / 10) }
        return .object(o)
    }
}
