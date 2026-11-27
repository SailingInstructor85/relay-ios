import Foundation

/// Entwürfe der Eingabefelder (Martin, 27.11.2026: „… und auch die Antwort war dann irgendwie weg“). Was in einem
/// Feld getippt oder diktiert ist und noch nicht gesendet wurde, steht nicht nur im Speicher der App, sondern je Feld
/// in einer Datei auf dem iPhone. Stürzt die App ab oder beendet iOS sie im Hintergrund, steht der Text beim nächsten
/// Öffnen wieder im Feld. Der Entwurf ist immer das, was gerade im Feld steht (während eines Diktats zusätzlich das
/// bis dahin Erkannte): Ein geleertes Feld, also auch ein gesendeter Text, löscht ihn.
public enum Drafts {
    /// Das Jarvis-Feld.
    public static let jarvis = "jarvis"
    /// Der Chat mit dem Vault-Agenten.
    public static let vault = "vault"
    /// Das Formular „Fehler melden“.
    public static let report = "fehlermeldung"
    /// Der Chat einer Sitzung.
    public static func session(_ key: String) -> String { "session:" + key }
    /// Das Antwortfeld einer Rückfrage; dasselbe in „Rückfrage jetzt“, „Dein Zug“ und den Hinweisen.
    public static func question(_ ref: String) -> String { "question:" + ref }

    /// Fürs Nutzungsprotokoll: welche Art Feld (ohne Sitzungsschlüssel oder Kennung der Rückfrage).
    public static func kind(_ key: String) -> String {
        if key.hasPrefix("session:") { return "sitzung" }
        if key.hasPrefix("question:") { return "rückfrage" }
        return key
    }

    /// Frühestens so viele Sekunden nach einer Änderung wird geschrieben; weitere Änderungen in dieser Zeit gehen
    /// im selben Schreibvorgang auf. Beim Wechsel in den Hintergrund wird sofort geschrieben.
    public static let saveDelay = 0.5

    /// Was als Entwurf gilt: der Text im Feld, während eines Diktats dahinter das bis jetzt Erkannte.
    public static func combined(typed: String, heard: String) -> String {
        let h = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.isEmpty { return typed }
        if typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return h }
        return typed.hasSuffix(" ") || typed.hasSuffix("\n") ? typed + h : typed + " " + h
    }

    /// Beim Öffnen eines Felds: der Text, der hineingehört, oder nil, wenn nichts zu tun ist. Ein Feld, in dem schon
    /// etwas steht, wird nie überschrieben.
    public static func restore(field: String, stored: String) -> String? {
        guard field.isEmpty, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return stored
    }
}

/// Alle Entwürfe, je Feld einer. Reine Daten: Die App lädt und schreibt die Datei (`DraftStore`).
public struct DraftBook: Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var text: String
        /// Letzte Änderung (Sekunden seit 1970).
        public var ts: Double
        public init(text: String, ts: Double) {
            self.text = text
            self.ts = ts
        }
    }

    /// Ältere Entwürfe verfallen (eine Sitzung oder Rückfrage, die es längst nicht mehr gibt).
    public static let maxAge: Double = 30 * 86400
    /// Höchstens so viele Entwürfe; darüber gehen die ältesten.
    public static let maxCount = 100
    /// Längere Texte werden nicht gesichert (ein versehentlich eingefügtes Riesendokument).
    public static let maxLength = 200_000

    public private(set) var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) { self.entries = entries }

    public var isEmpty: Bool { entries.isEmpty }

    /// Der Entwurf eines Felds, "" wenn es keinen gibt.
    public func text(_ key: String) -> String { entries[key]?.text ?? "" }

    /// Setzt den Entwurf eines Felds; leerer Text (auch nur Leerzeichen) löscht ihn. true, wenn sich etwas geändert
    /// hat und geschrieben werden muss.
    @discardableResult
    public mutating func set(_ key: String, _ text: String, now: Double) -> Bool {
        guard !key.isEmpty else { return false }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return remove(key) }
        guard text.count <= Self.maxLength else { return false }
        if entries[key]?.text == text { return false }
        entries[key] = Entry(text: text, ts: now)
        return true
    }

    @discardableResult
    public mutating func remove(_ key: String) -> Bool {
        entries.removeValue(forKey: key) != nil
    }

    /// Räumt auf: zu alte Entwürfe und, über `maxCount` hinaus, die ältesten. true, wenn etwas entfernt wurde.
    @discardableResult
    public mutating func prune(now: Double) -> Bool {
        let before = entries.count
        entries = entries.filter { now - $0.value.ts <= Self.maxAge }
        if entries.count > Self.maxCount {
            let keep = entries.sorted { $0.value.ts != $1.value.ts ? $0.value.ts > $1.value.ts : $0.key < $1.key }.prefix(Self.maxCount)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        return entries.count != before
    }

    public func encode() -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try? e.encode(entries)
    }

    /// Eine fehlende oder beschädigte Datei ergibt ein leeres Buch, nie einen Fehler.
    public static func decode(_ data: Data) -> DraftBook {
        DraftBook(entries: (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:])
    }
}
