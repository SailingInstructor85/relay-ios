import XCTest
@testable import RelayCore

final class AgendaTests: XCTestCase {
    // Antwort von calendar, Felder wie gateway/src/notifyd/agenda.py (merge, _event).
    private let json = """
    {"from": "2026-11-22", "to": "2026-11-29",
     "events": [
       {"id": "a1", "title": "Urlaub", "start": "2026-11-21", "end": "2026-11-23", "all_day": true, "source": "cal:Privat",
        "calendar": "Privat", "recurring": false},
       {"id": "b1", "title": "Zahnarzt", "start": "2026-11-22 09:30", "end": "2026-11-22 10:15", "all_day": false,
        "source": "cal:Privat", "calendar": "Privat", "recurring": false, "location": "Praxis am Markt"},
       {"id": "b2", "title": "", "start": "2026-11-22 08:00", "end": "2026-11-22 08:00", "all_day": false,
        "source": "cal:Planung", "calendar": "Planung", "recurring": true, "status": "tentative"},
       {"id": "c1", "title": "Nachtfahrt", "start": "2026-11-22 22:00", "end": "2026-11-23 02:00", "all_day": false,
        "source": "cal:Planung", "calendar": "Planung", "recurring": false},
       {"id": "c2", "title": "Abendrunde", "start": "2026-11-23 20:00", "end": "2026-11-24 00:00", "all_day": false,
        "source": "cal:Privat", "calendar": "Privat", "recurring": false},
       {"id": "d1", "title": "Messe", "start": "2026-11-24 10:00", "end": "2026-11-26 16:00", "all_day": false,
        "source": "owa:Arbeit", "calendar": "Arbeit", "recurring": false, "read_only": true},
       {"id": "x", "title": "ohne Start", "start": "", "end": ""}
     ],
     "sources": [
       {"key": "cal:Privat", "label": "Privat", "color": "#1E88E5", "kind": "cal", "count": 3, "read_only": false, "error": "",
        "synced": "2026-11-22 08:55"},
       {"key": "cal:Planung", "label": "Planung", "color": "#43a047", "kind": "cal", "count": 2, "read_only": false, "error": ""},
       {"key": "owa:Arbeit", "label": "Arbeit", "color": "blau", "kind": "owa", "count": 1, "read_only": true, "error": "not fetched yet"}
     ],
     "warnings": ["Calendar tool: timeout", ""]}
    """

    private var feed: CalendarFeed { CalendarFeed.from(JSON.parse(json)!) }

    func testDecoding() {
        let f = feed
        XCTAssertEqual(f.from, "2026-11-22")
        XCTAssertEqual(f.to, "2026-11-29")
        XCTAssertEqual(f.events.count, 6)
        XCTAssertEqual(f.warnings, ["Calendar tool: timeout"])
        let z = f.events[1]
        XCTAssertEqual(z.title, "Zahnarzt")
        XCTAssertEqual(z.startDay, "2026-11-22")
        XCTAssertEqual(z.startTime, "09:30")
        XCTAssertEqual(z.endTime, "10:15")
        XCTAssertEqual(z.location, "Praxis am Markt")
        XCTAssertFalse(z.allDay)
        XCTAssertEqual(f.events[2].title, Agenda.noTitle)
        XCTAssertTrue(f.events[2].recurring)
        XCTAssertEqual(f.events[2].status, "tentative")
        XCTAssertTrue(f.events[5].readOnly)
        XCTAssertEqual(f.events[0].startTime, "")
        XCTAssertEqual(f.sources.map { $0.label }, ["Privat", "Planung", "Arbeit"])
        XCTAssertEqual(f.sources[0].colorHex, 0x1E88E5)
        XCTAssertEqual(f.sources[1].colorHex, 0x43A047)
        XCTAssertNil(f.sources[2].colorHex)
        XCTAssertEqual(f.sources[0].synced, "2026-11-22 08:55")
        XCTAssertEqual(f.sources[2].error, "not fetched yet")
        XCTAssertEqual(f.colorHex(z), 0x1E88E5)
        XCTAssertEqual(CalendarFeed.from(.null).events, [])
    }

    func testLastDay() {
        let f = feed
        XCTAssertEqual(f.events[0].lastDay, "2026-11-23") // ganztägig: Ende zählt mit
        XCTAssertEqual(f.events[1].lastDay, "2026-11-22")
        XCTAssertEqual(f.events[3].lastDay, "2026-11-23") // bis 02:00 am Folgetag
        XCTAssertEqual(f.events[4].lastDay, "2026-11-23") // endet genau um Mitternacht
        XCTAssertEqual(CalendarEvent(id: "e", title: "t", start: "2026-11-22 09:00").lastDay, "2026-11-22")
        XCTAssertEqual(CalendarEvent(id: "e", title: "t", start: "2026-11-22", end: "2026-11-20", allDay: true).lastDay, "2026-11-22")
    }

    func testEntriesOfADay() {
        let today = Agenda.entries(feed, day: "2026-11-22")
        XCTAssertEqual(today.map { $0.event.title }, ["Urlaub", Agenda.noTitle, "Zahnarzt", "Nachtfahrt"])
        XCTAssertEqual(today.map { $0.time }, ["ganztägig", "08:00", "09:30", "22:00"])
        XCTAssertEqual(today.map { $0.until }, ["", "", "10:15", ""])
        XCTAssertEqual(today.map { $0.wholeDay }, [true, false, false, false])
        XCTAssertEqual(today[2].colorHex, 0x1E88E5)
        XCTAssertEqual(today[2].id, "2026-11-22|b1")

        let tomorrow = Agenda.entries(feed, day: "2026-11-23")
        XCTAssertEqual(tomorrow.map { $0.event.title }, ["Urlaub", "Nachtfahrt", "Abendrunde"])
        XCTAssertEqual(tomorrow.map { $0.time }, ["ganztägig", "bis 02:00", "20:00"])
        XCTAssertEqual(tomorrow[2].until, "00:00")

        // Abendrunde endet um Mitternacht und steht am 24. nicht mehr; die Messe beginnt
        XCTAssertEqual(Agenda.entries(feed, day: "2026-11-24").map { $0.event.title }, ["Messe"])
        XCTAssertEqual(Agenda.entries(feed, day: "2026-11-24").map { $0.time }, ["10:00"])
        XCTAssertEqual(Agenda.entries(feed, day: "2026-11-24").map { $0.until }, [""])
        // mittlerer Tag eines langen Termins
        XCTAssertEqual(Agenda.entries(feed, day: "2026-11-25").map { $0.time }, ["ganztägig"])
        XCTAssertEqual(Agenda.entries(feed, day: "2026-11-26").map { $0.time }, ["bis 16:00"])
        XCTAssertEqual(Agenda.entries(feed, day: "2026-11-27"), [])
    }

    func testCardAndDays() {
        let card = Agenda.card(feed, today: "2026-11-22")
        XCTAssertEqual(card.map { $0.label }, ["Heute", "Morgen"])
        XCTAssertEqual(card.map { $0.entries.count }, [4, 3])
        let week = Agenda.days(feed, from: "2026-11-22", count: 7, today: "2026-11-22")
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week[3].label, "Mi., 25. November")
        XCTAssertEqual(week[6].date, "2026-11-28")
        XCTAssertTrue(week[5].entries.isEmpty)
        XCTAssertEqual(Agenda.days(feed, from: "2026-11-22", count: 0, today: "2026-11-22"), [])
    }

    func testPast() {
        let today = Agenda.entries(feed, day: "2026-11-22")
        let urlaub = today[0], frueh = today[1], zahnarzt = today[2], nacht = today[3]
        XCTAssertFalse(urlaub.isPast(today: "2026-11-22", clock: "23:59"))
        XCTAssertTrue(frueh.isPast(today: "2026-11-22", clock: "08:00"))
        XCTAssertFalse(zahnarzt.isPast(today: "2026-11-22", clock: "10:00"))
        XCTAssertTrue(zahnarzt.isPast(today: "2026-11-22", clock: "10:15"))
        XCTAssertFalse(nacht.isPast(today: "2026-11-22", clock: "23:30"))
        XCTAssertTrue(zahnarzt.isPast(today: "2026-11-23", clock: "00:00"))
        XCTAssertFalse(zahnarzt.isPast(today: "2026-11-21", clock: "23:00"))
        let tomorrow = Agenda.entries(feed, day: "2026-11-23")
        XCTAssertTrue(tomorrow[1].isPast(today: "2026-11-23", clock: "02:00"))   // Nachtfahrt bis 02:00
        XCTAssertFalse(tomorrow[2].isPast(today: "2026-11-23", clock: "23:59"))  // Abendrunde bis Mitternacht
    }

    func testCoversAndTexts() {
        let f = feed
        XCTAssertTrue(f.covers("2026-11-22", days: 8))
        XCTAssertFalse(f.covers("2026-11-23", days: 8))
        XCTAssertFalse(f.covers("2026-11-21", days: 2))
        XCTAssertFalse(CalendarFeed(from: "", to: "", events: []).covers("2026-11-22", days: 1))
        XCTAssertEqual(Agenda.more(7, limit: 5), "2 weitere")
        XCTAssertEqual(Agenda.more(6, limit: 5), "1 weiterer")
        XCTAssertEqual(Agenda.more(5, limit: 5), "")
        XCTAssertEqual(Agenda.detail(f.events[1]), "Praxis am Markt · Privat")
        XCTAssertEqual(Agenda.detail(f.events[0]), "Privat")
        XCTAssertEqual(Agenda.hex("#FFFFFF"), 0xFFFFFF)
        XCTAssertNil(Agenda.hex("FFFFFF"))
        XCTAssertNil(Agenda.hex("#GGGGGG"))
    }

    func testFailureLine() {
        XCTAssertNil(Agenda.failureLine(message: "unknown rpc 'calendar'", remote: true))
        XCTAssertEqual(Agenda.failureLine(message: "from must be YYYY-MM-DD and days a number", remote: true),
                       "Kalender nicht geladen: from must be YYYY-MM-DD and days a number")
        XCTAssertNotNil(Agenda.failureLine(message: "Zeitüberschreitung", remote: false))
    }

    // MARK: Zwischenspeicher (Kalender ohne Verbindung)

    private var berlin: TimeZone { TimeZone(identifier: "Europe/Berlin")! }
    /// 26.11.2026 11:35 in Berlin (MEZ, UTC+1).
    private let fetched: Double = 1795689300

    func testCacheRoundTrip() throws {
        let response = try XCTUnwrap(JSON.parse(json))
        let data = try XCTUnwrap(CalendarCache.encode(response, at: fetched))
        let snap = try XCTUnwrap(CalendarCache.decode(data))
        XCTAssertEqual(snap.at, fetched)
        XCTAssertEqual(snap.feed, CalendarFeed.from(response))
        XCTAssertEqual(snap.feed.events.count, 6)
        XCTAssertEqual(snap.feed.sources.first?.colorHex, 0x1E88E5)
        XCTAssertEqual(Agenda.card(snap.feed, today: "2026-11-22").map { $0.entries.count }, [4, 3])
    }

    func testCacheRejectsBrokenFiles() {
        XCTAssertNil(CalendarCache.decode(Data()))
        XCTAssertNil(CalendarCache.decode(Data("kein json".utf8)))
        XCTAssertNil(CalendarCache.decode(Data(#"{"at": 5}"#.utf8)))
        XCTAssertNil(CalendarCache.decode(Data(#"{"at": 0, "feed": {"from": "2026-11-22", "to": "2026-11-29", "events": []}}"#.utf8)))
        XCTAssertNil(CalendarCache.decode(Data(#"{"at": 5, "feed": {"events": []}}"#.utf8)), "ohne Zeitraum")
        XCTAssertNil(CalendarCache.encode(.null, at: fetched))
        XCTAssertNotNil(CalendarCache.decode(Data(#"{"at": 5, "feed": {"from": "2026-11-22", "to": "2026-11-29", "events": []}}"#.utf8)))
    }

    func testCacheUsableUntilItsLastDay() {
        let feed = CalendarFeed.from(JSON.parse(json)!)
        XCTAssertTrue(CalendarCache.usable(feed, today: "2026-11-22"))
        XCTAssertTrue(CalendarCache.usable(feed, today: "2026-11-29"))
        XCTAssertFalse(CalendarCache.usable(feed, today: "2026-11-30"))
        XCTAssertFalse(CalendarCache.usable(CalendarFeed(from: "", to: "", events: []), today: "2026-11-22"))
    }

    func testCacheNote() {
        XCTAssertEqual(DayText.key(ts: fetched, timeZone: berlin), "2026-11-26")
        // am selben Tag nur die Uhrzeit
        XCTAssertEqual(CalendarCache.note(at: fetched, now: fetched + 3600, timeZone: berlin), "Stand von 11:35")
        // älter als heute: mit dem Tag
        XCTAssertEqual(CalendarCache.note(at: fetched, now: fetched + 2 * 86400, timeZone: berlin), "Stand von Do., 26. November, 11:35")
        // aus dem Vorjahr: mit Jahreszahl
        XCTAssertEqual(CalendarCache.note(at: fetched, now: fetched + 60 * 86400, timeZone: berlin), "Stand von Do., 26. November 2026, 11:35")
    }

    func testStaleNoteOnlyWhenNotFresh() {
        let now = fetched + 600
        // frisch geladen und verbunden: kein Hinweis
        XCTAssertNil(CalendarCache.staleNote(at: fetched, stale: false, connected: true, now: now, timeZone: berlin))
        // aus dem Zwischenspeicher, auch wenn die Verbindung schon steht (bis der neue Abruf da ist)
        XCTAssertEqual(CalendarCache.staleNote(at: fetched, stale: true, connected: true, now: now, timeZone: berlin), "Stand von 11:35")
        // Verbindung verloren, der Stand im Speicher altert
        XCTAssertEqual(CalendarCache.staleNote(at: fetched, stale: false, connected: false, now: now, timeZone: berlin), "Stand von 11:35")
        // gar kein Stand
        XCTAssertNil(CalendarCache.staleNote(at: 0, stale: true, connected: false, now: now, timeZone: berlin))
    }

    func testDaysOutsideTheCachedRangeAreNotLoaded() {
        // Stand vom 22. bis 29.11., geöffnet am 28.11.: Die Woche reicht bis zum 4.12., bekannt ist sie bis zum 29.
        let feed = CalendarFeed.from(JSON.parse(json)!)
        let week = Agenda.days(feed, from: "2026-11-28", count: 7, today: "2026-11-28")
        XCTAssertEqual(week.map(\.loaded), [true, true, false, false, false, false, false])
        XCTAssertEqual(week[0].emptyText, "Keine Termine")
        XCTAssertEqual(week[2].emptyText, "Noch nicht geladen")
        // am letzten Tag des Stands: heute bekannt, morgen nicht
        XCTAssertEqual(Agenda.card(feed, today: "2026-11-29").map(\.loaded), [true, false])
        // frisch geladen (heute der erste Tag): alles bekannt
        XCTAssertTrue(Agenda.days(feed, from: "2026-11-22", count: 7, today: "2026-11-22").allSatisfy(\.loaded))
        // ein Gateway ohne Zeitraum in der Antwort: wie bisher „Keine Termine“
        let open = CalendarFeed(from: "", to: "", events: [])
        XCTAssertTrue(Agenda.card(open, today: "2026-11-22").allSatisfy(\.loaded))
    }
}
