import Foundation

/// Tab „Heute“: was die Übersicht des Tages zeigt. Eine Zeile je laufender Sitzung (Modell, Kontext, Status,
/// Kurztext), die Pille in der Kopfzeile, die kompakte Fassung von „Braucht dich“ und der Text der Assistent-Karte.
/// Vorbild ist „Today“ der Android-App (TeamUi.kt), dort mit Teammitgliedern statt Sitzungen.
public enum Today {
    public enum Status: Int, Sendable, Equatable {
        /// Wartet auf den Nutzer (Frage, Freigabedialog, fragender Schluss).
        case waits
        /// Arbeitet gerade.
        case working
        /// Bereit, wartet auf nichts.
        case idle
    }

    /// Eine Karte im Abschnitt „Sitzungen“.
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: String { key }
        public let key: String
        public let title: String
        /// Modell und Kontext, „opus 5.5 · 130k ctx“. Leer, wenn das Gateway keinen Kontext meldet.
        public let meta: String
        /// Stufe des Kontexts für die Farbe: 0 unauffällig, 1 groß, 2 voll.
        public let contextLevel: Int
        public let status: Status
        /// Zeichen und Wort des Status: „! wartet“, „◐ arbeitet“, „○ bereit“.
        public let statusText: String
        /// Kurztext, auf eine Zeile geglättet: bei wartenden Sitzungen die Frage, sonst die letzte Nachricht.
        public let preview: String
        public let lastActivity: Double
        public let cwd: String
        public let alias: String
        public let folder: String
        public let unread: Bool
        public let pinned: Bool
    }

    /// Die laufenden Sitzungen für „Heute“: ohne beendete, geschlossene, ruhende, ohne Hintergrundläufe und ohne die,
    /// die gerade geschlossen werden (`hidden`). Reihenfolge: wartet, dann arbeitet, dann der Rest; darin angeheftete
    /// zuerst, dann zuletzt aktiv. Unabhängig vom Umschalter „Laufend/Zuletzt“ der Sitzungsliste.
    public static func rows(_ sessions: [Session], unread: Set<String> = [], pinned: Set<String> = [], hidden: Set<String> = [],
                            limit: Int? = nil) -> [Row] {
        let live = sessions.filter { s in
            !hidden.contains(s.key) && !s.background && !s.exited && !s.closed && !s.hibernated
        }
        let rows = live.map { s in row(s, unread: unread.contains(s.key), pinned: pinned.contains(s.key)) }
            .sorted { a, b in
                if a.status != b.status { return a.status.rawValue < b.status.rawValue }
                if a.pinned != b.pinned { return a.pinned }
                if a.lastActivity != b.lastActivity { return a.lastActivity > b.lastActivity }
                return a.key < b.key
            }
        if let limit, rows.count > limit { return Array(rows.prefix(limit)) }
        return rows
    }

    public static func row(_ s: Session, unread: Bool = false, pinned: Bool = false) -> Row {
        let st = status(s)
        return Row(key: s.key, title: s.name, meta: s.context?.label ?? "", contextLevel: contextLevel(s.context), status: st,
                   statusText: statusText(st), preview: flat(st == .waits ? YourTurn.sessionText(s) : s.lastMessage),
                   lastActivity: s.lastActivity, cwd: s.cwd, alias: s.alias, folder: s.folder, unread: unread, pinned: pinned)
    }

    public static func status(_ s: Session) -> Status {
        if s.waits { return .waits }
        return s.state == "busy" ? .working : .idle
    }

    public static func statusText(_ st: Status) -> String {
        switch st {
        case .waits: return "! wartet"
        case .working: return "◐ arbeitet"
        case .idle: return "○ bereit"
        }
    }

    /// 0 unauffällig (`ok` oder unbekannt), 2 voll (`full`), sonst 1.
    public static func contextLevel(_ c: SessionContext?) -> Int {
        guard let c, c.level != "ok", !c.level.isEmpty else { return 0 }
        return c.level == "full" ? 2 : 1
    }

    /// Zeilenumbrüche und mehrfache Leerzeichen zu einem Leerzeichen, damit eine Vorschau ihre Zeilen füllt.
    public static func flat(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    // MARK: Kopfzeile

    public struct Pill: Sendable, Equatable {
        public let text: String
        /// true: jemand wartet (rote Pille), false: nur Ungelesenes.
        public let urgent: Bool
    }

    /// Die Pille in der Kopfzeile: wer wartet, hat Vorrang vor Ungelesenem. `waiting`: Zahl aus „Dein Zug“.
    public static func pill(waiting: Int, unread: Int) -> Pill? {
        if waiting > 0 { return Pill(text: waiting == 1 ? "1 braucht dich" : "\(waiting) brauchen dich", urgent: true) }
        if unread > 0 { return Pill(text: "\(unread) ungelesen", urgent: false) }
        return nil
    }

    // MARK: Braucht dich (kompakt)

    /// Eine Zeile im Abschnitt „Braucht dich“ auf „Heute“; die volle Karte steht in „Dein Zug“.
    public struct Need: Sendable, Equatable, Identifiable {
        public let id: String
        /// Art des Eintrags („Rückfrage“, „Freigabe“ …).
        public let label: String
        public let title: String
        /// Die Frage, auf eine Zeile geglättet.
        public let text: String
        public let since: Double
    }

    /// Die ersten `limit` Einträge aus „Dein Zug“ (dort schon das Älteste zuerst) und wie viele darüber hinaus warten.
    public static func needs(_ items: [YourTurn.Item], limit: Int = 3) -> (shown: [Need], more: Int) {
        let shown = items.prefix(max(0, limit)).map {
            Need(id: $0.id, label: YourTurn.kindLabel($0.kind), title: $0.title, text: flat($0.text), since: $0.since)
        }
        return (Array(shown), max(0, items.count - shown.count))
    }

    /// Beschriftung des Verweises auf „Dein Zug“ unter den kompakten Zeilen.
    public static func needsLink(more: Int) -> String {
        if more <= 0 { return "In „Dein Zug“ beantworten" }
        return more == 1 ? "1 weiterer in „Dein Zug“" : "\(more) weitere in „Dein Zug“"
    }

    // MARK: Assistent

    public static let assistantName = "Jarvis"
    public static let assistantHint = "Frag unten, was gerade läuft oder was ansteht."
    public static let assistantPlaceholder = "Jarvis fragen…"

    /// Text der Assistent-Karte: die letzte Antwort auf diesem iPhone, geglättet; ohne Verlauf ein Hinweis.
    public static func assistantPreview(_ turns: [JarvisTurn]) -> String {
        guard let last = turns.last else { return assistantHint }
        let a = flat(last.a)
        return a.isEmpty ? flat(last.q) : a
    }

    /// Zeit der letzten Antwort (Unix-Sekunden), 0 ohne Verlauf.
    public static func assistantLast(_ turns: [JarvisTurn]) -> Double { turns.last?.ts ?? 0 }
}
