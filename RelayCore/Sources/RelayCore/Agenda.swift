import Foundation

// Kalender (PROTOCOL.md des Gateways, RPC `calendar`; Code in gateway/src/notifyd/agenda.py). Nur lesend. Zeiten
// kommen als lokale Zeit des PCs: `JJJJ-MM-TT HH:MM`, ganztägige Termine als `JJJJ-MM-TT` mit dem letzten Tag
// einschließlich. Ein mehrtägiger Termin steht einmal in der Liste, die App verteilt ihn auf seine Tage.

/// Ein Termin aus `events`.
public struct CalendarEvent: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// `JJJJ-MM-TT HH:MM`, ganztägig `JJJJ-MM-TT`.
    public let start: String
    public let end: String
    public let allDay: Bool
    /// Schlüssel der Quelle (`sources[].key`), zum Beispiel `cal:Privat`.
    public let source: String
    /// Name des Kalenders zur Anzeige.
    public let calendar: String
    public let recurring: Bool
    public let location: String
    public let organizer: String
    public let description: String
    /// `busy`, `tentative`, `free`, `oof`, `workingelsewhere` oder leer.
    public let status: String
    public let readOnly: Bool

    public init(id: String, title: String, start: String, end: String = "", allDay: Bool = false, source: String = "",
                calendar: String = "", recurring: Bool = false, location: String = "", organizer: String = "",
                description: String = "", status: String = "", readOnly: Bool = false) {
        self.id = id; self.title = title; self.start = start; self.end = end.isEmpty ? start : end; self.allDay = allDay
        self.source = source; self.calendar = calendar; self.recurring = recurring; self.location = location
        self.organizer = organizer; self.description = description; self.status = status; self.readOnly = readOnly
    }

    /// Ein Eintrag aus `events`. Ohne lesbaren Starttag entfällt er.
    public static func from(_ o: JSON) -> CalendarEvent? {
        let start = o.str("start")
        guard DayText.parts(start) != nil else { return nil }
        let title = o.str("title").trimmingCharacters(in: .whitespacesAndNewlines)
        let id = o.str("id")
        return CalendarEvent(id: id.isEmpty ? "\(o.str("source"))|\(title)|\(start)" : id, title: title.isEmpty ? Agenda.noTitle : title,
                             start: start, end: o.str("end"), allDay: o.flag("all_day"), source: o.str("source"),
                             calendar: o.str("calendar"), recurring: o.flag("recurring"), location: o.str("location"),
                             organizer: o.str("organizer"), description: o.str("description"), status: o.str("status"),
                             readOnly: o.flag("read_only"))
    }

    public var startDay: String { String(start.prefix(10)) }

    /// Uhrzeit des Beginns „09:30“, leer bei ganztägigen Terminen.
    public var startTime: String { CalendarEvent.time(start, allDay: allDay) }
    public var endTime: String { CalendarEvent.time(end, allDay: allDay) }

    /// Der letzte Tag, an dem der Termin zu sehen ist. Ganztägig: das Ende zählt mit. Mit Uhrzeit: Endet der Termin
    /// genau um Mitternacht eines späteren Tages, gehört dieser Tag nicht mehr dazu.
    public var lastDay: String {
        let endDay = DayText.parts(end) == nil ? startDay : String(end.prefix(10))
        if endDay <= startDay { return startDay }
        if !allDay && endTime == "00:00" { return DayText.add(endDay, -1) }
        return endDay
    }

    private static func time(_ s: String, allDay: Bool) -> String {
        guard !allDay, s.count >= 16 else { return "" }
        let t = s.dropFirst(11).prefix(5)
        let p = t.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0...23).contains(h), (0...59).contains(m) else { return "" }
        return String(format: "%02d:%02d", h, m)
    }
}

/// Ein Kalender aus `sources`: Name, Farbe und Zustand.
public struct CalendarSource: Sendable, Hashable, Identifiable {
    public let key: String
    public let label: String
    /// `#RRGGBB`.
    public let color: String
    /// `cal` oder `owa`.
    public let kind: String
    public let count: Int
    public let readOnly: Bool
    public let error: String
    /// Letzter Abruf eines Feeds (lokale Zeit als Text), leer wenn unbekannt.
    public let synced: String
    public var id: String { key }

    public init(key: String, label: String, color: String = "", kind: String = "cal", count: Int = 0, readOnly: Bool = false,
                error: String = "", synced: String = "") {
        self.key = key; self.label = label; self.color = color; self.kind = kind; self.count = count; self.readOnly = readOnly
        self.error = error; self.synced = synced
    }

    public static func from(_ o: JSON) -> CalendarSource? {
        let key = o.str("key")
        guard !key.isEmpty else { return nil }
        return CalendarSource(key: key, label: o.str("label", key), color: o.str("color"), kind: o.str("kind", "cal"),
                              count: o["count"].int ?? 0, readOnly: o.flag("read_only"), error: o.str("error"), synced: o.str("synced"))
    }

    /// Die Farbe als 0xRRGGBB; nil, wenn das Gateway keine gültige nennt.
    public var colorHex: UInt32? { Agenda.hex(color) }
}

/// Antwort von `calendar`.
public struct CalendarFeed: Sendable, Equatable {
    public let from: String
    public let to: String
    public let events: [CalendarEvent]
    public let sources: [CalendarSource]
    public let warnings: [String]

    public init(from: String, to: String, events: [CalendarEvent], sources: [CalendarSource] = [], warnings: [String] = []) {
        self.from = from; self.to = to; self.events = events; self.sources = sources; self.warnings = warnings
    }

    public static func from(_ o: JSON) -> CalendarFeed {
        CalendarFeed(from: o.str("from"), to: o.str("to"), events: o["events"].array.compactMap(CalendarEvent.from),
                     sources: o["sources"].array.compactMap(CalendarSource.from),
                     warnings: o["warnings"].array.compactMap { $0.string }.filter { !$0.isEmpty })
    }

    /// Farbe des Kalenders, aus dem der Termin stammt.
    public func colorHex(_ e: CalendarEvent) -> UInt32? { sources.first { $0.key == e.source }?.colorHex }

    /// Der Zeitraum reicht für `days` Tage ab `day` (sonst muss neu geladen werden).
    public func covers(_ day: String, days: Int) -> Bool {
        !from.isEmpty && !to.isEmpty && from <= day && DayText.add(day, max(days, 1) - 1) <= to
    }
}

public enum Agenda {
    public static let noTitle = "(ohne Titel)"
    public static let allDay = "ganztägig"
    public static let emptyDay = "Keine Termine"
    public static let missingTitle = "Gateway liefert keinen Kalender"

    /// Ein Termin an einem bestimmten Tag.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let event: CalendarEvent
        public let day: String
        /// Linke Spalte: Beginn „09:30“, „ganztägig“, oder am letzten Tag eines Termins über Mitternacht „bis 02:00“.
        public let time: String
        /// Zweite Zeile der linken Spalte: Ende „10:15“, leer bei ganztägig oder ohne Ende.
        public let until: String
        /// Zählt an diesem Tag als ganztägig (auch die mittleren Tage eines langen Termins mit Uhrzeit).
        public let wholeDay: Bool
        public let colorHex: UInt32?
        public var id: String { day + "|" + event.id }

        /// Der Termin ist zu dieser Uhrzeit (`HH:MM`) an `today` schon vorbei.
        public func isPast(today: String, clock: String) -> Bool {
            if day < today { return true }
            guard day == today, !wholeDay else { return false }
            if event.lastDay > day { return false }
            let end = event.endTime.isEmpty ? event.startTime : event.endTime
            return !end.isEmpty && end <= clock && !(event.endTime == "00:00" && event.end.prefix(10) > event.startDay)
        }
    }

    /// Ein Tag mit seinen Terminen.
    public struct Day: Sendable, Equatable, Identifiable {
        public let date: String
        public let label: String
        public let entries: [Entry]
        public var id: String { date }
    }

    /// Die Termine eines Tages: ganztägige zuerst, dann nach Uhrzeit.
    public static func entries(_ feed: CalendarFeed, day: String) -> [Entry] {
        let found = feed.events.compactMap { e -> Entry? in
            guard e.startDay <= day, day <= e.lastDay else { return nil }
            let color = feed.colorHex(e)
            if e.allDay { return Entry(event: e, day: day, time: allDay, until: "", wholeDay: true, colorHex: color) }
            let first = day == e.startDay, last = day == e.lastDay
            if first {
                let until = last && e.endTime != e.startTime ? e.endTime : ""
                return Entry(event: e, day: day, time: e.startTime.isEmpty ? allDay : e.startTime, until: until,
                             wholeDay: e.startTime.isEmpty, colorHex: color)
            }
            if last, !e.endTime.isEmpty {
                return Entry(event: e, day: day, time: "bis \(e.endTime)", until: "", wholeDay: false, colorHex: color)
            }
            return Entry(event: e, day: day, time: allDay, until: "", wholeDay: true, colorHex: color)
        }
        func sortTime(_ e: Entry) -> String { e.wholeDay ? "" : (e.day == e.event.startDay ? e.event.startTime : "00:00") }
        return found.enumerated().sorted { a, b in
            if a.element.wholeDay != b.element.wholeDay { return a.element.wholeDay }
            let ta = sortTime(a.element), tb = sortTime(b.element)
            return ta != tb ? ta < tb : a.offset < b.offset
        }.map { $0.element }
    }

    /// `count` Tage ab `from`, auch leere, beschriftet relativ zu `today` („Heute“, „Morgen“, „Mi., 25. November“).
    public static func days(_ feed: CalendarFeed, from: String, count: Int, today: String) -> [Day] {
        (0..<max(count, 0)).map { i in
            let d = DayText.add(from, i)
            return Day(date: d, label: DayText.label(d, today: today), entries: entries(feed, day: d))
        }
    }

    /// Kalenderkarte auf „Heute“: heute und morgen.
    public static func card(_ feed: CalendarFeed, today: String) -> [Day] { days(feed, from: today, count: 2, today: today) }

    /// Wie viele Termine eine Liste über `limit` hinaus hat, als Text „2 weitere“; leer, wenn alle Platz haben.
    public static func more(_ count: Int, limit: Int) -> String {
        let n = count - limit
        return n <= 0 ? "" : (n == 1 ? "1 weiterer" : "\(n) weitere")
    }

    /// `#RRGGBB` -> 0xRRGGBB.
    public static func hex(_ color: String) -> UInt32? {
        guard color.count == 7, color.hasPrefix("#") else { return nil }
        return UInt32(color.dropFirst(), radix: 16)
    }

    /// Zeile unter dem Titel: Ort und Kalender, „Raum 2 · Privat“.
    public static func detail(_ e: CalendarEvent) -> String {
        [e.location.trimmingCharacters(in: .whitespacesAndNewlines), e.calendar].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Was die Karte zeigt, wenn `calendar` scheitert; nil, wenn das Gateway den RPC gar nicht kennt (dann bleibt die
    /// Karte auf „Heute“ weg, die Wochenliste nennt den Grund).
    public static func failureLine(message: String, remote: Bool) -> String? {
        if remote && InboxText.isUnknownRpc(message) { return nil }
        return "Kalender nicht geladen: \(message)"
    }
}
