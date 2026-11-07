import Foundation

// Routinen des Gateways (PROTOCOL.md „Team, handoffs and routines“ → „Routines“): die Einträge der routines.yaml des
// Teams, ihr Zeitplan und letzter Lauf, dazu die systemd-Timer des Benutzers (nur anzeigen). Ohne `team:`-Block in der
// Gateway-Konfiguration antworten alle RPCs mit `enabled: false`; die App zeigt dann „Routinen im Gateway nicht
// eingerichtet“. Nachbau der Android-Reiter „Routines“ (TeamModel.kt, TeamUi.kt).

/// Ein Lauf einer Routine: `ok` ist nil, solange er läuft.
public struct RoutineRun: Sendable, Hashable {
    public let at: Double
    public let ok: Bool?
    public let summary: String
    public let handoff: String?
    public init(at: Double, ok: Bool?, summary: String = "", handoff: String? = nil) {
        self.at = at; self.ok = ok; self.summary = summary; self.handoff = handoff
    }
    public static func from(_ o: JSON) -> RoutineRun? {
        guard o.object != nil else { return nil }
        return RoutineRun(at: o.num("at"), ok: o["ok"].bool, summary: o.str("summary"), handoff: o["handoff"].string.flatMap { $0.isEmpty ? nil : $0 })
    }
    public var running: Bool { ok == nil }
}

public struct Routine: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let owner: String
    public let when: String?
    public let on: String?
    public let kind: String       // builtin | prompt | system
    public let mode: String
    public let deliver: String
    public var enabled: Bool
    public let note: String
    public let description: String
    public let nextRun: Double?
    public var last: RoutineRun?
    public let builtin: String    // "brief" | "checkin" | ""

    public init(id: String, title: String, owner: String = "chief", when: String? = nil, on: String? = nil, kind: String = "builtin",
                mode: String = "read-only", deliver: String = "log", enabled: Bool = true, note: String = "", description: String = "",
                nextRun: Double? = nil, last: RoutineRun? = nil, builtin: String = "") {
        self.id = id; self.title = title; self.owner = owner; self.when = when; self.on = on; self.kind = kind; self.mode = mode
        self.deliver = deliver; self.enabled = enabled; self.note = note; self.description = description; self.nextRun = nextRun
        self.last = last; self.builtin = builtin
    }

    public static func from(_ o: JSON) -> Routine? {
        let id = o.str("id")
        guard !id.isEmpty else { return nil }
        func opt(_ k: String) -> String? { let v = o.str(k); return v.isEmpty ? nil : v }
        let title = o.str("title")
        return Routine(id: id, title: title.isEmpty ? id : title, owner: o.str("owner", "chief"), when: opt("when"), on: opt("on"),
                       kind: o.str("kind", "builtin"), mode: o.str("mode", "read-only"), deliver: o.str("deliver", "log"),
                       enabled: o.flag("enabled", true), note: o.str("note"), description: o.str("description").trimmingCharacters(in: .whitespacesAndNewlines),
                       nextRun: o["next_run"].double, last: RoutineRun.from(o["last"]), builtin: o.str("builtin"))
    }

    /// Ein systemd-Timer (`kind: system`) wird nur angezeigt; der Zeitplan und „Jetzt ausführen“ gehören systemd.
    public var isSystem: Bool { kind == "system" }
}

/// Ein systemd-Timer des Benutzers, den keine Routine nennt (Abschnitt „System“, nur anzeigen).
public struct SystemTimer: Sendable, Hashable, Identifiable {
    public var id: String { unit }
    public let unit: String
    public let description: String
    public let next: Double?
    public let last: Double?
    public let result: String
    public init(unit: String, description: String = "", next: Double? = nil, last: Double? = nil, result: String = "") {
        self.unit = unit; self.description = description; self.next = next; self.last = last; self.result = result
    }
    public static func from(_ o: JSON) -> SystemTimer? {
        let unit = o.str("unit")
        guard !unit.isEmpty else { return nil }
        return SystemTimer(unit: unit, description: o.str("description"), next: o["next"].double, last: o["last"].double, result: o.str("result"))
    }
    /// „relay-nachtbau“ statt „relay-nachtbau.timer“.
    public var name: String { unit.hasSuffix(".timer") ? String(unit.dropLast(6)) : unit }
    public var failed: Bool { !result.isEmpty && result != "success" }
}

/// Die Antwort auf rpc `routines`.
public struct RoutinesInfo: Sendable, Equatable {
    public var enabled: Bool
    public var routines: [Routine]
    public var system: [SystemTimer]
    public init(enabled: Bool = false, routines: [Routine] = [], system: [SystemTimer] = []) {
        self.enabled = enabled; self.routines = routines; self.system = system
    }
    public static let off = RoutinesInfo()

    public static func from(_ o: JSON) -> RoutinesInfo {
        guard o.flag("enabled") else { return .off }
        return RoutinesInfo(enabled: true, routines: o["routines"].array.compactMap(Routine.from), system: o["system"].array.compactMap(SystemTimer.from))
    }

    /// Der Lauf aus dem Ereignis `routine_run` (`{id, at, ok, summary, handoff}`) ersetzt den letzten Lauf der Routine.
    public func applying(runEvent ev: JSON) -> RoutinesInfo {
        let id = ev.str("id")
        guard !id.isEmpty, let run = RoutineRun.from(ev) else { return self }
        var copy = self
        copy.routines = routines.map { r in
            guard r.id == id else { return r }
            var c = r; c.last = run; return c
        }
        return copy
    }

    /// Mit dem Ergebnis von `routine_set` (`{routine}`) oder, wenn es fehlt, nur dem Schalter.
    public func applying(set id: String, enabled: Bool, result: JSON) -> RoutinesInfo {
        var copy = self
        copy.routines = routines.map { r in
            guard r.id == id else { return r }
            if let fresh = Routine.from(result["routine"]) { return fresh }
            var c = r; c.enabled = enabled; return c
        }
        return copy
    }

    /// Routinen nach Besitzer, Reihenfolge des ersten Auftretens; der Chef zuerst.
    public var byOwner: [RoutineGroup] {
        var order: [String] = []
        var groups: [String: [Routine]] = [:]
        for r in routines {
            if groups[r.owner] == nil { order.append(r.owner) }
            groups[r.owner, default: []].append(r)
        }
        if let i = order.firstIndex(of: "chief"), i > 0 { order.remove(at: i); order.insert("chief", at: 0) }
        return order.map { RoutineGroup(owner: $0, routines: groups[$0] ?? []) }
    }
}

/// Die Routinen eines Besitzers (Abschnitt der Liste).
public struct RoutineGroup: Sendable, Equatable, Identifiable {
    public var id: String { owner }
    public let owner: String
    public let routines: [Routine]
    public init(owner: String, routines: [Routine]) { self.owner = owner; self.routines = routines }
}

/// Texte für Zeitplan und Läufe (Deutsch), Suche und das Anliegen „Neue Routine“ an den Chef.
public enum RoutinesText {
    public static let disabledTitle = "Routinen im Gateway nicht eingerichtet"
    public static let disabledText = "Das Gateway hat keinen team:-Block in seiner Konfiguration (roster und routines). Ohne ihn gibt es keine Routinen, keine Timer-Übersicht und keinen Chef, der neue Routinen anlegt. Einrichtung: docs/routinen.md im Repo relay-ios."
    /// Mitglied, das „Neue Routine“ entgegennimmt (der Chef des Rosters; PROTOCOL.md `team_send {to: "chief"}`).
    public static let chief = "chief"

    static let weekday: [String: String] = ["mon": "Mo", "tue": "Di", "wed": "Mi", "thu": "Do", "fri": "Fr", "sat": "Sa", "sun": "So"]

    /// „weekdays 08:00“ -> „werktags 08:00“, „daily 07:40“ -> „täglich 07:40“, „mon,thu 09:00, 14:00“ -> „Mo, Do 09:00, 14:00“,
    /// „monthly 1 09:00“ -> „monatlich am 1. um 09:00“, „sun 18:00“ -> „So 18:00“; Unbekanntes bleibt.
    public static func when(_ spec: String?) -> String {
        guard let spec = spec?.trimmingCharacters(in: .whitespaces), !spec.isEmpty else { return "" }
        let parts = spec.split(separator: " ", maxSplits: 1).map(String.init)
        let head = parts[0].lowercased()
        let rest = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        switch head {
        case "weekdays": return ["werktags", rest].filter { !$0.isEmpty }.joined(separator: " ")
        case "daily": return ["täglich", rest].filter { !$0.isEmpty }.joined(separator: " ")
        case "monthly":
            let p = rest.split(separator: " ", maxSplits: 1).map(String.init)
            if p.count == 2 { return "monatlich am \(p[0]). um \(p[1])" }
            return ["monatlich", rest].filter { !$0.isEmpty }.joined(separator: " ")
        default:
            let days = head.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            if days.allSatisfy({ weekday[$0] != nil }) {
                return ([days.compactMap { weekday[$0] }.joined(separator: ", ")] + (rest.isEmpty ? [] : [rest])).joined(separator: " ")
            }
            return spec
        }
    }

    /// „in 3 Std. 10 Min.“, „in 45 Min.“, „in 2 T.“, „jetzt“; nil für die Vergangenheit.
    public static func inWords(_ seconds: Double) -> String? {
        guard seconds >= -60 else { return nil }
        if seconds < 60 { return "jetzt" }
        let m = Int(seconds / 60)
        if m < 60 { return "in \(m) Min." }
        let h = m / 60
        if h < 24 { return m % 60 == 0 ? "in \(h) Std." : "in \(h) Std. \(m % 60) Min." }
        return "in \(h / 24) T."
    }

    /// Zeitplanzeile einer Routine: Zeitplan, Ereignis, nächster Lauf; „ausgeschaltet“ statt des nächsten Laufs.
    public static func schedule(_ r: Routine, now: Double) -> String {
        var parts: [String] = []
        let w = when(r.when)
        if !w.isEmpty { parts.append(w) }
        if let on = r.on, !on.isEmpty { parts.append("bei \(on)") }
        if r.isSystem { parts.append("systemd-Timer") }
        if !r.enabled && !r.isSystem { parts.append("ausgeschaltet") }
        else if let n = r.nextRun, let s = inWords(n - now) { parts.append("nächster Lauf \(s)") }
        if parts.isEmpty { parts.append("kein Zeitplan") }
        return parts.joined(separator: " · ")
    }

    /// Letzter Lauf: „läuft…“, „zuletzt vor 2 Std.: ok“, „zuletzt vor 1 T.: Fehler“, „noch nie gelaufen“.
    public static func lastRun(_ r: Routine, now: Double) -> String {
        guard let l = r.last else { return "noch nie gelaufen" }
        if l.running { return "läuft…" }
        let ago = TermText.ago(l.at, now: Date(timeIntervalSince1970: now))
        let when = ago.isEmpty || ago == "jetzt" ? "gerade" : "vor \(ago)"
        return "zuletzt \(when): " + (l.ok == true ? "ok" : "Fehler")
    }

    /// Die Zeile eines systemd-Timers: nächster Lauf, letzter Lauf, Ergebnis.
    public static func timerLine(_ t: SystemTimer, now: Double) -> String {
        var parts: [String] = []
        if let n = t.next, let s = inWords(n - now) { parts.append("nächster \(s)") }
        if let l = t.last, l > 0 {
            let ago = TermText.ago(l, now: Date(timeIntervalSince1970: now))
            parts.append(ago == "jetzt" ? "zuletzt gerade" : "zuletzt vor \(ago)")
        }
        if !t.result.isEmpty { parts.append(t.result == "success" ? "ok" : t.result) }
        return parts.isEmpty ? "keine Angaben" : parts.joined(separator: " · ")
    }

    /// Das Ergebnis von „Jetzt ausführen“ (`routine_run` -> `{run}`) in einem Satz.
    public static func runResult(_ r: JSON) -> String {
        guard let run = RoutineRun.from(r["run"]) else { return "Gestartet." }
        if run.running { return "Läuft…" }
        let s = run.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return (run.ok == true ? "Fertig" : "Fehlgeschlagen") + (s.isEmpty ? "." : ": \(s)")
    }

    /// Das Anliegen an den Chef, der den Eintrag in routines.yaml schreibt und bestätigen lässt (Android: „New routine: …“).
    public static func newRoutineRequest(_ text: String) -> String {
        "Neue Routine: " + text.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n(Bitte den Eintrag in routines.yaml vorschlagen, mit id, title, description, when, owner und enabled: false, und mich vor dem Aktivieren bestätigen lassen.)"
    }

    /// Routinen, deren Titel, Beschreibung, Kennung oder Zeitplan alle Wörter der Suche enthalten.
    public static func search(_ routines: [Routine], query: String) -> [Routine] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return routines.filter { AppSearch.matches("\($0.title) \($0.description) \($0.id) \(when($0.when))", q) }
    }
}
