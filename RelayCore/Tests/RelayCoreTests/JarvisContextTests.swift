import XCTest
@testable import RelayCore

final class JarvisContextTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func ts(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Double {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!.timeIntervalSince1970
    }

    func testDayStartsAtFour() {
        XCTAssertEqual(JarvisContext.day(ts(2026, 11, 24, 12), calendar: cal), "2026-11-24")
        // nach Mitternacht gehört das Gespräch noch zum Abend davor
        XCTAssertEqual(JarvisContext.day(ts(2026, 11, 25, 1, 30), calendar: cal), "2026-11-24")
        XCTAssertEqual(JarvisContext.day(ts(2026, 11, 25, 3, 59), calendar: cal), "2026-11-24")
        XCTAssertEqual(JarvisContext.day(ts(2026, 11, 25, 4, 0), calendar: cal), "2026-11-25")
        // Monatswechsel
        XCTAssertEqual(JarvisContext.day(ts(2026, 12, 1, 2), calendar: cal), "2026-11-30")
    }

    func testBreaksAtDayChangeAndReset() {
        let times = [ts(2026, 11, 23, 22), ts(2026, 11, 24, 1), ts(2026, 11, 24, 9), ts(2026, 11, 24, 10), ts(2026, 11, 24, 11)]
        XCTAssertEqual(JarvisContext.breaks(times: times, resets: [], calendar: cal), [2])
        // Knopf zwischen dem vierten und fünften Zug
        XCTAssertEqual(JarvisContext.breaks(times: times, resets: [ts(2026, 11, 24, 10, 30)], calendar: cal), [2, 4])
        // ein Zurücksetzen vor dem ersten oder nach dem letzten Zug trennt im Verlauf nichts
        XCTAssertEqual(JarvisContext.breaks(times: times, resets: [ts(2026, 11, 23, 8), ts(2026, 11, 24, 12)], calendar: cal), [2])
        XCTAssertEqual(JarvisContext.breaks(times: [], resets: [], calendar: cal), [])
        XCTAssertEqual(JarvisContext.breaks(times: [ts(2026, 11, 24, 9)], resets: [], calendar: cal), [])
    }

    func testBreakPending() {
        let last = ts(2026, 11, 24, 22)
        XCTAssertFalse(JarvisContext.breakPending(last: last, now: ts(2026, 11, 24, 23), resets: [], calendar: cal))
        XCTAssertFalse(JarvisContext.breakPending(last: last, now: ts(2026, 11, 25, 3), resets: [], calendar: cal))
        XCTAssertTrue(JarvisContext.breakPending(last: last, now: ts(2026, 11, 25, 8), resets: [], calendar: cal))
        XCTAssertTrue(JarvisContext.breakPending(last: last, now: ts(2026, 11, 24, 23), resets: [ts(2026, 11, 24, 22, 30)], calendar: cal))
        XCTAssertFalse(JarvisContext.breakPending(last: nil, now: ts(2026, 11, 25, 8), resets: [], calendar: cal))
    }

    func testResetListIsCapped() {
        var r: [Double] = []
        for i in 0..<60 { r = JarvisContext.adding(Double(i), to: r) }
        XCTAssertEqual(r.count, 50)
        XCTAssertEqual(r.last, 59)
        XCTAssertEqual(r.first, 10)
    }

    func testStatus() {
        let s = JarvisContext.status(["bytes": 150_000, "max_bytes": 600_000])
        XCTAssertEqual(s, JarvisContext.Status(bytes: 150_000, maxBytes: 600_000))
        XCTAssertEqual(s?.percent, 25)
        XCTAssertEqual(s.map(JarvisContext.fillLabel), "Gespräch am PC zu 25 % gefüllt")
        XCTAssertEqual(JarvisContext.status(["bytes": 900_000, "max_bytes": 600_000])?.percent, 100)
        XCTAssertNil(JarvisContext.status(["bytes": 5]))
        XCTAssertNil(JarvisContext.status([:]))
    }

    func testLeadFromContext() {
        // der Chief führt das Gespräch und lässt sich auf Zuruf ablösen
        let l = JarvisContext.lead(JSON.obj(["lead": .string("Chief"), "hand_over": .bool(true)]))
        XCTAssertEqual(l, JarvisContext.Lead(name: "Chief"))
        XCTAssertEqual(l.map(JarvisContext.leadLabel), "Chief führt das Gespräch")
        XCTAssertEqual(JarvisContext.handOverLabel("Chief"), "Chief ablösen")
        // schon erbeten: steht in der Überschrift
        let asked = JarvisContext.lead(JSON.obj(["lead": .string("Chief"), "hand_over": .bool(true), "asked_at": .number(1_795_000_000)]))
        XCTAssertEqual(asked?.askedAt, 1_795_000_000)
        XCTAssertEqual(asked.map(JarvisContext.leadLabel), "Chief führt das Gespräch · Ablösung erbeten")
        // ein Gateway ohne Ablösung auf Zuruf (leere Antwort, oder Lead ohne das Feld): kein Menüpunkt
        XCTAssertNil(JarvisContext.lead(JSON.obj([:])))
        XCTAssertNil(JarvisContext.lead(JSON.obj(["lead": .string("Chief")])))
        XCTAssertNil(JarvisContext.lead(JSON.obj(["lead": .string("  "), "hand_over": .bool(true)])))
        // der Überblicks-Agent mit Füllstand ist kein Lead, und ein Lead hat keinen Füllstand
        XCTAssertNil(JarvisContext.lead(JSON.obj(["bytes": .number(10), "max_bytes": .number(100)])))
        XCTAssertNil(JarvisContext.status(JSON.obj(["lead": .string("Chief"), "hand_over": .bool(true)])))
    }

    func testHandOverNotice() {
        let asked = JarvisContext.handOverNotice(JSON.obj(["lead": .string("Chief"), "asked": .bool(true)]))
        XCTAssertEqual(asked?.hasPrefix("Chief schreibt jetzt seine Notizen"), true)
        let none = JarvisContext.handOverNotice(JSON.obj(["lead": .string("Chief"), "asked": .bool(false)]))
        XCTAssertEqual(none?.hasPrefix("Für Chief läuft gerade keine Sitzung"), true)
        // Antwort ohne Namen: der Name aus dem Menü
        XCTAssertEqual(JarvisContext.handOverNotice(JSON.obj(["asked": .bool(true)]), fallbackName: "Chief")?.hasPrefix("Chief schreibt"), true)
        // der Überblicks-Agent antwortet leer: kein Hinweis zur Ablösung
        XCTAssertNil(JarvisContext.handOverNotice(JSON.obj([:])))
    }
}
