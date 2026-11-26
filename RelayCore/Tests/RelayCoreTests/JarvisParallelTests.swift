import XCTest
@testable import RelayCore

final class JarvisParallelTests: XCTestCase {
    func testProgressKinds() {
        XCTAssertEqual(RpcProgress.kind(JSON.obj(["type": .string("rpc_progress"), "id": .string("a"), "delta": .string("Hal")])), .delta("Hal"))
        XCTAssertEqual(RpcProgress.kind(JSON.obj(["id": .string("a"), "status": .string("taken"), "handoff": .string("H-7")])), .status("taken"))
        // eine Zeile ohne beides bleibt ein leeres Textstück wie bisher
        XCTAssertEqual(RpcProgress.kind(JSON.obj(["id": .string("a")])), .delta(""))
    }

    func testStatusLabel() {
        XCTAssertEqual(JarvisAsk.statusLabel(JSON.obj(["status": .string("taken"), "name": .string("Chief"), "handoff": .string("H-7")])), "Chief hat es")
        XCTAssertEqual(JarvisAsk.statusLabel(JSON.obj(["status": .string("taken")])), "Jarvis hat es")
        XCTAssertNil(JarvisAsk.statusLabel(JSON.obj(["status": .string("queued"), "name": .string("Chief")])))
        XCTAssertNil(JarvisAsk.statusLabel(JSON.obj(["delta": .string("taken")])))
    }

    func testPendingLabel() {
        XCTAssertNil(JarvisAsk.pendingLabel(0))
        XCTAssertNil(JarvisAsk.pendingLabel(1))
        XCTAssertEqual(JarvisAsk.pendingLabel(3), "3 Antworten stehen noch aus. Du kannst weiterschreiben.")
    }

    private func sayEvent(tag: String = "jarvis-say-12", title: String = "Zugverbindung Hamburg", text: String = "Der ICE um 9:28 passt.") -> JSON {
        JSON.obj(["type": .string("notice"), "seq": .number(41), "ts": .number(1_795_000_000), "kind": .string("jarvis_say"),
                  "title": .string(title), "text": .string(text), "tag": .string(tag), "source": .string("chief")])
    }

    func testSayBecomesTurnWithTopic() {
        let t = JarvisSay.turn(from: sayEvent(), now: 5)
        XCTAssertEqual(t?.topic, "Zugverbindung Hamburg")
        XCTAssertEqual(t?.a, "Der ICE um 9:28 passt.")
        XCTAssertEqual(t?.q, "")
        XCTAssertEqual(t?.ref, "jarvis-say-12")
        XCTAssertEqual(t?.ts, 1_795_000_000)
        XCTAssertEqual(t?.voice, false)
        // ein gewöhnlicher Hinweis gehört nicht in den Chat
        XCTAssertNil(JarvisSay.turn(from: JSON.obj(["type": .string("notice"), "title": .string("Backup"), "text": .string("fertig")]), now: 5))
        // ohne Text nichts, ohne Thema eine neutrale Überschrift, ohne tag die Folgenummer
        XCTAssertNil(JarvisSay.turn(from: sayEvent(text: "  "), now: 5))
        XCTAssertEqual(JarvisSay.turn(from: sayEvent(title: ""), now: 5)?.topic, JarvisSay.noTopic)
        XCTAssertEqual(JarvisSay.turn(from: sayEvent(tag: ""), now: 5)?.ref, "s41")
    }

    func testSayIsStoredOnce() {
        let old = [JarvisTurn(q: "Such mir einen Zug", a: "Mach ich, ich melde mich.", voice: false, ts: 1)]
        let say = JarvisSay.turn(from: sayEvent(), now: 5)!
        let stored = JarvisSay.adding(say, to: old)
        XCTAssertEqual(stored?.count, 2)
        XCTAssertEqual(stored?.last?.ref, "jarvis-say-12")
        // dieselbe Rückmeldung noch einmal (Replay nach einer Verbindungspause): keine Dublette
        XCTAssertNil(JarvisSay.adding(JarvisSay.turn(from: sayEvent(), now: 9)!, to: stored!))
        // eine zweite mit eigener Kennung kommt dazu
        XCTAssertEqual(JarvisSay.adding(JarvisSay.turn(from: sayEvent(tag: "jarvis-say-13"), now: 9)!, to: stored!)?.count, 3)
    }

    func testMergeKeepsSaysThatArrivedMeanwhile() {
        let q1 = JarvisTurn(q: "Frage 1", a: "Antwort 1", voice: false, ts: 1)
        let q2 = JarvisTurn(q: "Frage 2", a: "Antwort 2", voice: false, ts: 3)
        let say = JarvisSay.turn(from: sayEvent(), now: 2)!
        // die Ansicht kennt die Rückmeldung noch nicht, im Speicher steht sie schon
        let merged = JarvisSay.merge([q1, q2], stored: [q1, say])
        XCTAssertEqual(merged.map(\.a), ["Antwort 1", "Antwort 2", "Der ICE um 9:28 passt."])
        // kennt die Ansicht sie schon, bleibt es bei einer
        XCTAssertEqual(JarvisSay.merge([q1, say, q2], stored: [q1, say]).count, 3)
        XCTAssertEqual(JarvisSay.missing(in: [q1, say], stored: [q1, say]), [])
        // gewöhnliche Züge aus dem Speicher kommen nicht doppelt zurück
        XCTAssertEqual(JarvisSay.merge([q2], stored: [q1]).map(\.q), ["Frage 2"])
    }

    func testSpokenStartsWithTopic() {
        let say = JarvisSay.turn(from: sayEvent(), now: 2)!
        XCTAssertEqual(JarvisSay.spoken(say), "Zugverbindung Hamburg. Der ICE um 9:28 passt.")
        XCTAssertEqual(JarvisSay.spoken(JarvisSay.turn(from: sayEvent(title: "Fertig:"), now: 2)!), "Fertig: Der ICE um 9:28 passt.")
        XCTAssertEqual(JarvisSay.spoken(JarvisTurn(q: "x", a: "nur Text", voice: false)), "nur Text")
    }

    func testHistoryKeepsTopicAndReadsOldFiles() {
        let say = JarvisSay.turn(from: sayEvent(), now: 2)!
        let back = JarvisHistory.decode(JarvisHistory.encode([say])!)
        XCTAssertEqual(back.first?.topic, "Zugverbindung Hamburg")
        XCTAssertEqual(back.first?.ref, "jarvis-say-12")
        // ein Verlauf aus einer älteren Version ohne die neuen Felder
        let old = #"[{"id":"7C1F1C2E-0000-4000-8000-000000000001","q":"Was läuft?","a":"Zwei Sitzungen.","voice":false,"ts":10}]"#
        let turns = JarvisHistory.decode(Data(old.utf8))
        XCTAssertEqual(turns.count, 1)
        XCTAssertNil(turns.first?.topic)
        XCTAssertNil(turns.first?.ref)
        // die Suche findet eine Rückmeldung auch über ihr Thema
        XCTAssertEqual(JarvisHistory.search([say], query: "hamburg").count, 1)
    }
}
