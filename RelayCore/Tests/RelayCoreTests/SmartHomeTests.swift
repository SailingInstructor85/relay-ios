import XCTest
@testable import RelayCore

final class SmartHomeTests: XCTestCase {
    func testActionsAndParams() {
        XCTAssertEqual(SmartHome.tv.map(\.id), ["on", "hdmi2", "tv", "off"])
        XCTAssertEqual(SmartHome.tv.map(\.title), ["Fernseher einschalten", "HDMI 2 aktivieren", "Fernsehen", "Fernseher ausschalten"])
        let p = SmartHome.params(SmartHome.tv[1])
        XCTAssertEqual(p.str("device"), "tv")
        XCTAssertEqual(p.str("action"), "hdmi2")
        // nichts außer Gerät und Aktionsname geht an den PC
        XCTAssertEqual(p.object?.keys.sorted(), ["action", "device"])
    }

    func testOutcomeShowsTheScriptsLastLines() {
        let a = SmartHome.tv[1]
        XCTAssertEqual(SmartHome.outcome(["ok": true, "text": "Fernseher wird geweckt\n\nUmgeschaltet auf HDMI 2\n"], action: a),
                       SmartHome.Outcome(ok: true, text: "Fernseher wird geweckt\nUmgeschaltet auf HDMI 2"))
        XCTAssertEqual(SmartHome.outcome(["ok": false, "text": "Fernseher nicht erreichbar."], action: a),
                       SmartHome.Outcome(ok: false, text: "Fernseher nicht erreichbar."))
        XCTAssertEqual(SmartHome.outcome([:], action: a), SmartHome.Outcome(ok: true, text: "Erledigt: HDMI 2 aktivieren."))
        XCTAssertFalse(SmartHome.outcome(["ok": false], action: a).ok)
    }

    func testFailureTexts() {
        let old = SmartHome.failure(message: "unknown rpc 'smart_home'", remote: true)
        XCTAssertFalse(old.ok)
        XCTAssertTrue(old.text.contains("noch nicht schalten"))
        XCTAssertEqual(SmartHome.failure(message: "bad action", remote: true).text, "Das Gateway meldet: bad action")
        XCTAssertEqual(SmartHome.failure(message: "timeout", remote: false).text, "Keine Antwort vom PC: timeout")
    }

    func testCleanKeepsItShort() {
        XCTAssertEqual(SmartHome.clean("a\nb\nc\nd\ne\n"), "b\nc\nd\ne")
        XCTAssertTrue(SmartHome.clean(String(repeating: "x", count: 900)).hasSuffix(" …"))
    }
}
