import Foundation

// MARK: Nutzungsprotokoll (2026-11-07)

/// Ein Ereignis des Nutzungsprotokolls: was Martin wann in welcher Ansicht getan hat, dazu App-Zustände und Fehler.
/// Standard ohne Inhalte (Entscheidung Martin, 2026-11-06): von Text, Diktat und Fotos nur Art und Länge, von Fotos nie
/// die Bilddaten. Geht nur ans eigene Gateway (RPC `usage_put`), nie an fremde Dienste.
public struct UsageEvent: Codable, Equatable, Sendable {
    public var id: String
    public var ts: Double
    public var screen: String
    public var action: String
    public var session: String?
    public var appVersion: String
    /// Art des Inhalts: `text`, `diktat`, `foto`, `video`, `datei`, …
    public var kind: String?
    /// Länge in Zeichen (Text, Diktat) oder Bytes (Anhänge).
    public var length: Int?
    /// Kurze Zusatzangabe ohne Inhalt, zum Beispiel ein Zustand oder ein Pfad am PC.
    public var detail: String?
    /// Fehlertext, falls die Aktion fehlschlug.
    public var error: String?
    /// Schon beim Gateway angekommen.
    public var sent: Bool

    public init(id: String = UUID().uuidString, ts: Double, screen: String, action: String, session: String? = nil,
                appVersion: String, kind: String? = nil, length: Int? = nil, detail: String? = nil, error: String? = nil,
                sent: Bool = false) {
        self.id = id; self.ts = ts; self.screen = screen; self.action = action; self.session = session
        self.appVersion = appVersion; self.kind = kind; self.length = length
        self.detail = detail.map { String($0.prefix(UsageBuffer.maxDetail)) }
        self.error = error.map { String($0.prefix(UsageBuffer.maxDetail)) }
        self.sent = sent
    }

    /// So geht das Ereignis ans Gateway (ohne `sent`).
    public var wire: JSON {
        var o: [String: JSON] = ["id": .string(id), "ts": .number(ts), "screen": .string(screen), "action": .string(action),
                                 "app_version": .string(appVersion)]
        if let session { o["session"] = .string(session) }
        if let kind { o["kind"] = .string(kind) }
        if let length { o["length"] = .number(Double(length)) }
        if let detail { o["detail"] = .string(detail) }
        if let error { o["error"] = .string(error) }
        return .object(o)
    }
}

/// Der lokale Puffer: alle Ereignisse der letzten `keepDays` Tage, gesendete wie ungesendete. Ungesendete bleiben,
/// bis das Gateway sie bestätigt hat; bricht die Verbindung beim Senden ab, gehen sie beim nächsten Mal mit (das
/// Gateway entfernt Doppelte über `id`).
public struct UsageBuffer: Codable, Equatable, Sendable {
    public static let keepDays = 30
    public static let maxEvents = 5000
    public static let batch = 200
    static let maxDetail = 300

    public private(set) var events: [UsageEvent] = []

    public init(events: [UsageEvent] = []) { self.events = events }

    public var pendingCount: Int { events.filter { !$0.sent }.count }

    /// Neues Ereignis. Wird der Puffer zu groß, fallen zuerst die ältesten gesendeten weg, dann die ältesten überhaupt.
    public mutating func append(_ e: UsageEvent) {
        events.append(e)
        guard events.count > Self.maxEvents else { return }
        var over = events.count - Self.maxEvents
        events.removeAll { e in
            guard over > 0, e.sent else { return false }
            over -= 1
            return true
        }
        if over > 0 { events.removeFirst(over) }
    }

    /// Die nächsten ungesendeten Ereignisse, älteste zuerst.
    public func pending(limit: Int = UsageBuffer.batch) -> [UsageEvent] {
        Array(events.lazy.filter { !$0.sent }.prefix(limit))
    }

    /// Nach der Bestätigung des Gateways.
    public mutating func markSent(_ ids: [String]) {
        let set = Set(ids)
        for i in events.indices where set.contains(events[i].id) { events[i].sent = true }
    }

    /// Aufbewahrung: Ereignisse älter als `days` Tage fallen weg, auch ungesendete.
    public mutating func prune(now: Double, days: Int = UsageBuffer.keepDays) {
        let limit = now - Double(days) * 86400
        events.removeAll { $0.ts < limit }
    }

    /// Ereignisse der letzten `minutes` Minuten (für „Fehler melden“).
    public func recent(minutes: Double, now: Double) -> [UsageEvent] {
        let from = now - minutes * 60
        return events.filter { $0.ts >= from }
    }

    public mutating func clear() { events = [] }

    /// Parameter für `usage_put`.
    public static func putParams(_ batch: [UsageEvent]) -> JSON {
        .object(["items": .array(batch.map(\.wire))])
    }
}

/// Text der letzten Minuten, nur im Speicher der App. Er geht nur mit, wenn Martin bei „Fehler melden“ den Haken
/// „Inhalte mitsenden“ setzt (Entscheidung Martin, 2026-11-06). Fotos nie, nur ihr Pfad.
public struct RecentContent: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let ts: Double, screen: String, session: String?, kind: String, text: String
    }
    public static let keepSeconds: Double = 600
    public static let maxChars = 4000
    public private(set) var entries: [Entry] = []

    public init() {}

    public mutating func add(ts: Double, screen: String, session: String?, kind: String, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        entries.append(Entry(ts: ts, screen: screen, session: session, kind: kind, text: String(t.prefix(Self.maxChars))))
        prune(now: ts)
    }

    public mutating func prune(now: Double) {
        entries.removeAll { now - $0.ts > Self.keepSeconds }
    }

    public mutating func clear() { entries = [] }

    /// Was beim Haken „Inhalte mitsenden“ mitgeht.
    public func wire(now: Double) -> JSON {
        .array(entries.filter { now - $0.ts <= Self.keepSeconds }.map { e in
            var o: [String: JSON] = ["ts": .number(e.ts), "screen": .string(e.screen), "kind": .string(e.kind), "text": .string(e.text)]
            if let s = e.session { o["session"] = .string(s) }
            return .object(o)
        })
    }
}

/// „Fehler melden“: Beschreibung, die Ereignisse der letzten Minuten und, nur mit Haken, die Inhalte.
public enum UsageReport {
    public static let minutes: Double = 10
    public static let sendLabel = "Fehler melden"
    public static let contentsLabel = "Inhalte mitsenden"

    public static func params(text: String, buffer: UsageBuffer, contents: RecentContent?, appVersion: String, now: Double) -> JSON {
        var o: [String: JSON] = [
            "text": .string(text.trimmingCharacters(in: .whitespacesAndNewlines)),
            "app_version": .string(appVersion),
            "ts": .number(now),
            "minutes": .number(minutes),
            "events": .array(buffer.recent(minutes: minutes, now: now).map(\.wire)),
        ]
        if let contents { o["contents"] = contents.wire(now: now) }
        return .object(o)
    }

    /// Senden geht erst mit einer Beschreibung.
    public static func canSend(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }
}
