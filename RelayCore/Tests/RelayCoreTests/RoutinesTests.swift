import XCTest
@testable import RelayCore

final class RoutinesTests: XCTestCase {
    func fixture(_ name: String) throws -> JSON {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try XCTUnwrap(JSON.parse(try Data(contentsOf: url)))
    }

    func testParse() throws {
        let info = RoutinesInfo.from(try fixture("routines"))
        XCTAssertTrue(info.enabled)
        XCTAssertEqual(info.routines.map(\.id), ["morning-brief", "week-review", "stellen"])
        let brief = info.routines[0]
        XCTAssertEqual(brief.title, "Morgen-Briefing")
        XCTAssertEqual(brief.when, "weekdays 08:00")
        XCTAssertNil(brief.on)
        XCTAssertEqual(brief.builtin, "brief")
        XCTAssertEqual(brief.last?.ok, true)
        XCTAssertEqual(brief.last?.summary, "Briefing gesendet.")
        XCTAssertNil(brief.last?.handoff)
        XCTAssertEqual(brief.nextRun, 1794120000)
        let review = info.routines[1]
        XCTAssertFalse(review.enabled)
        XCTAssertNil(review.last)
        XCTAssertNil(review.nextRun)
        XCTAssertEqual(review.note, "Fasse die Woche in fünf Sätzen zusammen.")
        let stellen = info.routines[2]
        XCTAssertTrue(stellen.isSystem)
        XCTAssertEqual(stellen.last?.ok, false)
        XCTAssertEqual(stellen.last?.handoff, "H-12")
        XCTAssertEqual(info.system.map(\.name), ["relay-nachtbau", "dreaming-woche"])
        XCTAssertEqual(info.system[0].result, "success")
        XCTAssertFalse(info.system[0].failed)
        XCTAssertNil(info.system[1].last)
        XCTAssertEqual(info.byOwner.map(\.owner), ["chief", "jobs"])
        XCTAssertEqual(info.byOwner[0].routines.count, 2)
    }

    func testDisabledAndOdd() {
        XCTAssertEqual(RoutinesInfo.from(["enabled": false, "routines": [], "system": []]), .off)
        XCTAssertEqual(RoutinesInfo.from(.null), .off)
        XCTAssertEqual(RoutinesInfo.from(["enabled": true, "routines": [["title": "ohne id"], ["id": "x"]]]).routines.map(\.title), ["x"])
        XCTAssertNil(RoutineRun.from(.null))
        XCTAssertEqual(RoutineRun.from(["at": 5, "ok": .null])?.running, true)
    }

    func testRunEventAndSet() throws {
        var info = RoutinesInfo.from(try fixture("routines"))
        info = info.applying(runEvent: ["id": "week-review", "at": 1794040000, "ok": .null, "summary": "", "handoff": .null])
        XCTAssertEqual(info.routines[1].last?.running, true)
        info = info.applying(runEvent: ["id": "week-review", "at": 1794040000, "ok": true, "summary": "Fünf Sätze.", "handoff": "H-20"])
        XCTAssertEqual(info.routines[1].last?.ok, true)
        XCTAssertEqual(info.routines[1].last?.handoff, "H-20")
        XCTAssertEqual(info.applying(runEvent: ["id": "nix", "at": 1, "ok": true]), info)
        XCTAssertEqual(info.applying(runEvent: ["at": 1, "ok": true]), info)
        // routine_set: the gateway's routine wins, else only the switch changes
        let set1 = info.applying(set: "week-review", enabled: true, result: ["routine": ["id": "week-review", "title": "Wochenrückblick neu", "enabled": true]])
        XCTAssertEqual(set1.routines[1].title, "Wochenrückblick neu")
        XCTAssertTrue(set1.routines[1].enabled)
        let set2 = info.applying(set: "morning-brief", enabled: false, result: [:])
        XCTAssertFalse(set2.routines[0].enabled)
        XCTAssertEqual(set2.routines[0].title, "Morgen-Briefing")
    }

    func testTexts() throws {
        XCTAssertEqual(RoutinesText.when("weekdays 08:00"), "werktags 08:00")
        XCTAssertEqual(RoutinesText.when("daily 07:40"), "täglich 07:40")
        XCTAssertEqual(RoutinesText.when("sun 18:00"), "So 18:00")
        XCTAssertEqual(RoutinesText.when("mon,thu 09:00, 14:00"), "Mo, Do 09:00, 14:00")
        XCTAssertEqual(RoutinesText.when("monthly 1 09:00"), "monatlich am 1. um 09:00")
        XCTAssertEqual(RoutinesText.when("every 5 min"), "every 5 min")
        XCTAssertEqual(RoutinesText.when(nil), "")
        XCTAssertEqual(RoutinesText.inWords(30), "jetzt")
        XCTAssertEqual(RoutinesText.inWords(45 * 60), "in 45 Min.")
        XCTAssertEqual(RoutinesText.inWords(3 * 3600 + 600), "in 3 Std. 10 Min.")
        XCTAssertEqual(RoutinesText.inWords(2 * 3600), "in 2 Std.")
        XCTAssertEqual(RoutinesText.inWords(3 * 86400), "in 3 T.")
        XCTAssertNil(RoutinesText.inWords(-3600))

        let info = RoutinesInfo.from(try fixture("routines"))
        let now = 1794031200.0 + 1800  // 30 Minuten nach dem letzten Lauf des Briefings
        XCTAssertEqual(RoutinesText.schedule(info.routines[0], now: now), "werktags 08:00 · nächster Lauf in 1 T.")
        XCTAssertEqual(RoutinesText.schedule(info.routines[1], now: now), "Fr 17:00 · ausgeschaltet")
        XCTAssertEqual(RoutinesText.schedule(info.routines[2], now: now), "systemd-Timer")
        XCTAssertEqual(RoutinesText.lastRun(info.routines[0], now: now), "zuletzt vor 30 Min.: ok")
        XCTAssertEqual(RoutinesText.lastRun(info.routines[1], now: now), "noch nie gelaufen")
        XCTAssertEqual(RoutinesText.lastRun(info.routines[2], now: now), "zuletzt vor 2 Std.: Fehler")
        XCTAssertEqual(RoutinesText.lastRun(info.routines[0].withRun(RoutineRun(at: now, ok: nil)), now: now), "läuft…")
        XCTAssertEqual(RoutinesText.timerLine(info.system[0], now: now), "nächster jetzt · zuletzt vor 1 Std. · ok")
        XCTAssertEqual(RoutinesText.timerLine(info.system[1], now: now), "nächster in 13 Std. 30 Min.")
        XCTAssertEqual(RoutinesText.timerLine(SystemTimer(unit: "x.timer", result: "failed"), now: now), "failed")
        XCTAssertEqual(RoutinesText.runResult(["run": ["id": "a", "at": 1, "ok": true, "summary": "Alles gut."]]), "Fertig: Alles gut.")
        XCTAssertEqual(RoutinesText.runResult(["run": ["id": "a", "at": 1, "ok": false, "summary": ""]]), "Fehlgeschlagen.")
        XCTAssertEqual(RoutinesText.runResult(["run": ["id": "a", "at": 1, "ok": .null]]), "Läuft…")
        XCTAssertEqual(RoutinesText.runResult([:]), "Gestartet.")
        XCTAssertTrue(RoutinesText.newRoutineRequest("  Freitags um 17 Uhr die Woche zusammenfassen ").hasPrefix("Neue Routine: Freitags um 17 Uhr die Woche zusammenfassen\n"))
        XCTAssertEqual(RoutinesText.search(info.routines, query: "woche").map(\.id), ["week-review"])
        XCTAssertEqual(RoutinesText.search(info.routines, query: "werktags").map(\.id), ["morning-brief"])
        XCTAssertEqual(RoutinesText.search(info.routines, query: "").count, 0)
    }
}

private extension Routine {
    func withRun(_ r: RoutineRun) -> Routine { var c = self; c.last = r; return c }
}
