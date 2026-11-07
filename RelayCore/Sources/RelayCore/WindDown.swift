import Foundation

/// „Alle Sitzungen beenden“ (2026-11-06): Jede gewählte Sitzung bekommt die Abschlussnachricht, der Agent schreibt seine
/// Übergabe, danach beendet das Gateway die Sitzung (`wind_down`, Fortschritt per Event `wind_down` und
/// `wind_down_status`). Phasen und Texte hier, der Ablauf läuft im Gateway (winddown.py), damit er auch ohne die App
/// zu Ende kommt.
public enum WindDown {
    /// Die Abschlussnachricht an jeden Agenten. Dieselbe steht als Vorgabe im Gateway (winddown.py DEFAULT_TEXT);
    /// die App schickt sie mit, damit beide Seiten denselben Wortlaut haben.
    public static let message = """
        Martin schließt diese Sitzung jetzt. Bitte sauber beenden: Keine neuen Aufgaben anfangen. Offenes nicht verwerfen, \
        sondern festhalten, wie es die Regel „Übergabe“ in ~/.agents/AGENTS.md verlangt: Stand, offene Punkte und nächster \
        Schritt in die Projektnotiz des Projekts (gibt es keine, nach ~/.agents/docs/Übergabe <Datum> <Thema>.md), \
        offene Aufgaben als To-do dort eintragen. Danach eine Zeile an ~/.agents/docs/Übergaben.md anhängen: \
        „- <Datum Uhrzeit> · <Projekt oder Ordner> · <Pfad der Übergabe> · <ein Satz Stand>“. Antworte zum Schluss \
        nur mit einer Zeile „Übergabe: <Pfad der Übergabe>“ und stelle keine Rückfrage.
        """

    public static let defaultWaitSeconds = 600

    public enum Phase: String, Sendable, CaseIterable {
        case queued, waiting, moving, sending, writing, closing, closed, question, timeout, error

        public var label: String {
            switch self {
            case .queued: return "wartet"
            case .waiting: return "arbeitet noch, wartet auf das Ende"
            case .moving: return "wird am PC beendet und in tmux fortgesetzt"
            case .sending: return "sendet Abschlussnachricht"
            case .writing: return "schreibt Übergabe"
            case .closing: return "beendet"
            case .closed: return "beendet"
            case .question: return "hat eine Rückfrage gestellt, bleibt offen"
            case .timeout: return "nicht sauber beendet (Frist abgelaufen)"
            case .error: return "Fehler, bleibt offen"
            }
        }

        /// Die Sitzung ist durch (gut oder schlecht).
        public var isFinal: Bool { [.closed, .question, .timeout, .error].contains(self) }
        public var isGood: Bool { self == .closed }
    }

    public struct Item: Sendable, Equatable, Identifiable {
        public let key: String, title: String, phase: Phase, detail: String, handover: String
        public var id: String { key }

        public init(key: String, title: String, phase: Phase, detail: String = "", handover: String = "") {
            self.key = key; self.title = title; self.phase = phase; self.detail = detail; self.handover = handover
        }

        public static func from(_ o: JSON) -> Item? {
            let k = o.str("key")
            guard !k.isEmpty else { return nil }
            return Item(key: k, title: o.str("title"), phase: Phase(rawValue: o.str("phase")) ?? .queued,
                        detail: o.str("detail"), handover: o.str("handover"))
        }

        /// Die Zeile unter dem Titel.
        public var statusLine: String {
            var s = phase.label
            if phase == .closed, !handover.isEmpty { s += " · Übergabe: " + handover }
            if phase == .timeout, !handover.isEmpty { s += " · Übergabe: " + handover }
            if !detail.isEmpty, phase == .error || phase == .question || phase == .timeout { s += " · " + SubmitCheck.display(detail) }
            return s
        }
    }

    /// Alle Einträge einer `wind_down_status`-Antwort, in der Reihenfolge des Gateways.
    public static func items(in o: JSON) -> [Item] { o["items"].array.compactMap(Item.from) }

    /// Ein `wind_down`-Event ändert eine Zeile.
    public static func apply(_ ev: JSON, to items: [Item]) -> [Item] {
        guard let n = Item.from(ev) else { return items }
        return items.map { $0.key == n.key ? Item(key: n.key, title: n.title.isEmpty ? $0.title : n.title, phase: n.phase,
                                                   detail: n.detail, handover: n.handover.isEmpty ? $0.handover : n.handover) : $0 }
    }

    public static func allDone(_ items: [Item]) -> Bool { !items.isEmpty && items.allSatisfy { $0.phase.isFinal } }

    // MARK: Auswahl

    public enum Eligibility: Equatable, Sendable {
        /// kann mit, Hinweis (leer = nichts Besonderes)
        case ok(note: String)
        /// kann nicht mit, Grund
        case no(reason: String)

        public var selectable: Bool { if case .ok = self { return true }; return false }
        public var note: String {
            switch self {
            case .ok(let n): return n
            case .no(let r): return r
            }
        }
    }

    /// Welche Sitzungen der Dialog anbietet. Arbeitende werden nicht hart abgebrochen (das Gateway wartet erst das
    /// Ende der Runde ab). Eine Claude-Sitzung am PC ohne tmux wird dort beendet und in tmux fortgesetzt (wie `send`
    /// mit `move`); bei Codex und agy geht das nicht, die bleiben außen vor.
    public static func eligibility(_ s: Session) -> Eligibility {
        if !s.alive || s.exited { return .no(reason: "läuft nicht") }
        if s.background { return .no(reason: "Hintergrundlauf") }
        if s.placeholder { return .no(reason: "startet noch") }
        let outsideTmux = s.liveTmux == nil || !s.attachable
        if outsideTmux && s.tool != "claude" { return .no(reason: "am PC in einem Terminal ohne tmux: dort beenden") }
        var notes: [String] = []
        if outsideTmux { notes.append("am PC ohne tmux: wird dort beendet und in tmux fortgesetzt") }
        if s.state == "busy" { notes.append("arbeitet gerade, das Ende der Runde wird abgewartet") }
        if s.state == "needs_input" { notes.append("wartet auf eine Antwort") }
        return .ok(note: notes.joined(separator: "; "))
    }

    /// Die Sitzungen für den Dialog: zuerst die wählbaren, Arbeitende hinten; die anderen folgen ausgegraut.
    public static func candidates(_ sessions: [Session]) -> [Session] {
        let ok = sessions.filter { eligibility($0).selectable }.sorted { a, b in
            if (a.state == "busy") != (b.state == "busy") { return b.state == "busy" }
            return a.lastActivity > b.lastActivity
        }
        let rest = sessions.filter { !eligibility($0).selectable && $0.alive && !$0.exited && !$0.background }
            .sorted { $0.lastActivity > $1.lastActivity }
        return ok + rest
    }

    /// Alles Wählbare ist vorgewählt.
    public static func preselected(_ sessions: [Session]) -> Set<String> {
        Set(sessions.filter { eligibility($0).selectable }.map(\.key))
    }

    public static func confirmTitle(_ n: Int) -> String {
        n == 1 ? "Eine Sitzung beenden?" : "\(n) Sitzungen beenden?"
    }

    public static func buttonTitle(_ n: Int) -> String {
        n == 1 ? "Sitzung beenden" : "\(n) Sitzungen beenden"
    }

    /// Der Knopf im Bestätigungsdialog (anders als der Startknopf benannt, damit UI-Tests beide unterscheiden).
    public static let confirmButton = "Ja, jetzt beenden"

    // MARK: Zusammenfassung

    /// Der Text am Ende: wie viele sauber, wo die Übergaben liegen, was offen blieb.
    public static func summary(_ items: [Item]) -> String {
        guard !items.isEmpty else { return "" }
        let closed = items.filter { $0.phase == .closed }
        let bad = items.filter { $0.phase.isFinal && $0.phase != .closed }
        var lines: [String] = []
        lines.append(closed.count == items.count ? (items.count == 1 ? "Die Sitzung ist sauber beendet." : "Alle \(items.count) Sitzungen sind sauber beendet.")
                     : "\(closed.count) von \(items.count) Sitzungen sauber beendet.")
        let withPath = items.filter { !$0.handover.isEmpty }
        if !withPath.isEmpty {
            lines.append("Übergaben:")
            for i in withPath { lines.append("• \(i.title.isEmpty ? i.key : i.title): \(i.handover)") }
        }
        for i in bad { lines.append("• \(i.title.isEmpty ? i.key : i.title): \(i.phase.label)" + (i.detail.isEmpty ? "" : " (\(i.detail))")) }
        return lines.joined(separator: "\n")
    }
}
