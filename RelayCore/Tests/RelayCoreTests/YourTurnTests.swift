import XCTest
@testable import RelayCore

final class YourTurnTests: XCTestCase {
    private func sess(_ key: String, state: String = "idle", act: Double = 0, asks: Bool = false, asksText: String = "",
                      last: String = "", background: Bool = false, question: String? = nil) -> Session {
        var o: [String: JSON] = ["key": .string(key), "state": .string(state), "last_activity": .number(act), "asks": .bool(asks),
                                 "asks_text": .string(asksText), "last_message": .string(last), "cwd": "/home/m/relay-ios",
                                 "title": .string("Titel " + key), "background": .bool(background)]
        if let question { o["question"] = .object(["question": .string(question)]) }
        return Session.from(.object(o))!
    }

    private func notice(_ ref: String, ts: Double, tag: String?, text: String = "Soll ich pushen?\nKontext: Zweig ist fertig\nEmpfehlung: ja",
                        answer: String? = nil) -> Notice {
        Notice(ref: ref, ts: ts, title: "", text: text, source: "relay-ios", tag: tag, answer: answer)
    }

    private func req(_ id: String, created: Double, expires: Double, text: String = "Hallo", executor: String = "desktop") -> SendReq {
        SendReq(id: id, kind: "mail", executor: executor, app: "", conversation: "", text: text, summary: "Mail an x", requestedBy: "Jarvis",
                expiresAt: expires, createdAt: created)
    }

    private func cloud(_ id: String, state: String, at: Double) -> CloudSession {
        CloudSession.from(["id": .string(id), "title": .string("Cloud " + id), "repo": "m/relay", "state": .string(state),
                           "question": "Weiter?", "url": "https://claude.ai/code/x", "last_at": .number(at)])!
    }

    func testOldestFirstAcrossAllSources() {
        let items = YourTurn.items(
            sessions: [sess("claude:c1:a", state: "needs_input", act: 300, question: "Welche Variante?"), sess("claude:c1:b", act: 50)],
            notices: [notice("s1", ts: 100, tag: "rueckfrage:relay-ios:R1")],
            requests: [req("r1", created: 200, expires: 9000)],
            confirms: [Confirm(id: "k1", description: "Timer stellen", ts: 400)],
            cloud: [cloud("c9", state: "waiting", at: 250), cloud("c8", state: "running", at: 10)],
            now: 1000)
        XCTAssertEqual(items.map(\.id), ["question:s1", "approval:r1", "cloud:c9", "session:claude:c1:a", "confirm:k1"])
        XCTAssertEqual(items.map(\.kind), [.question, .approval, .cloud, .session, .confirm])
    }

    func testOnlyWaitingSessions() {
        let items = YourTurn.items(
            sessions: [sess("claude:c1:a", state: "busy", act: 1), sess("claude:c1:b", state: "idle", act: 2),
                       sess("claude:c1:c", state: "idle", act: 3, asks: true, asksText: "Soll ich?"),
                       sess("claude:c1:d", state: "needs_input", act: 4, background: true),
                       sess("claude:c1:tmux-x", state: "needs_input", act: 5),
                       sess("claude:c1:e", state: "exited", act: 6, asks: true)],
            notices: [], requests: [], confirms: [], cloud: [], now: 10)
        XCTAssertEqual(items.map(\.id), ["session:claude:c1:c"])
        XCTAssertEqual(items[0].text, "Soll ich?")
        XCTAssertEqual(items[0].subtitle, "c1 · relay-ios")
        XCTAssertEqual(items[0].target, .session(key: "claude:c1:c"))
        XCTAssertEqual(items[0].cwd, "/home/m/relay-ios")
    }

    func testSessionText() {
        XCTAssertEqual(YourTurn.sessionText(sess("claude:c1:a", state: "needs_input", last: "zuletzt", question: "Frage?")), "Frage?")
        XCTAssertEqual(YourTurn.sessionText(sess("claude:c1:a", state: "idle", asks: true, asksText: "Schluss?", last: "zuletzt")), "Schluss?")
        XCTAssertEqual(YourTurn.sessionText(sess("claude:c1:a", state: "needs_input", last: "zuletzt")), "zuletzt")
    }

    func testQuestionsOnlyOpenOnes() {
        let items = YourTurn.items(
            sessions: [],
            notices: [notice("s1", ts: 5, tag: "rueckfrage:relay-ios:R1"),
                      notice("s2", ts: 6, tag: "rueckfrage:relay-ios:R2", answer: "ja"),
                      notice("s3", ts: 7, tag: "meldung:relay-ios:M1"),
                      notice("s4", ts: 8, tag: "quota-c1"),
                      notice("s5", ts: 9, tag: "rueckfrage:vault:R3", text: "Nur eine Frage")],
            requests: [], confirms: [], cloud: [], now: 10)
        XCTAssertEqual(items.map(\.id), ["question:s1", "question:s5"])
        XCTAssertEqual(items[0].title, "Rückfrage R1 von relay-ios")
        XCTAssertEqual(items[0].text, "Soll ich pushen?")
        XCTAssertEqual(items[0].context, "Zweig ist fertig")
        XCTAssertEqual(items[0].recommendation, "ja")
        XCTAssertEqual(items[0].target, .question(ref: "s1", agent: "relay-ios", quick: "ja"))
        XCTAssertEqual(items[1].target, .question(ref: "s5", agent: "vault", quick: nil))
    }

    func testApprovalsGroupedAndExpiredDropped() {
        let items = YourTurn.items(
            sessions: [], notices: [],
            requests: [req("r1", created: 100, expires: 5000), req("r2", created: 300, expires: 5200), req("r3", created: 50, expires: 900),
                       req("r4", created: 60, expires: 5000, text: "Anderer Text"), req("r5", created: 10, expires: 5000, text: "Telefon", executor: "phone")],
            confirms: [], cloud: [], now: 1000)
        XCTAssertEqual(items.map(\.id), ["approval:r4", "approval:r2"])
        let group = items[1]
        XCTAssertEqual(group.target, .approval(newest: "r2", all: ["r2", "r1"]))
        XCTAssertEqual(group.since, 100)
        XCTAssertEqual(group.repeats, 2)
        XCTAssertEqual(group.expiresAt, 5200)
        XCTAssertEqual(group.title, "E-Mail freigeben?")
        XCTAssertEqual(group.subtitle, "Angefragt von Jarvis")
        XCTAssertEqual(group.text, "Mail an x\n\nHallo")
        XCTAssertEqual(YourTurn.repeatsNote(2), "2 gleiche Anfragen. Freigeben beantwortet nur die neueste.")
        XCTAssertNil(YourTurn.repeatsNote(1))
    }

    func testUnknownTimeSortsFirstAndTiesAreStable() {
        let items = YourTurn.items(
            sessions: [sess("claude:c1:a", state: "needs_input", act: 7)],
            notices: [notice("s1", ts: 7, tag: "rueckfrage:relay-ios:R1")],
            requests: [],
            confirms: [Confirm(id: "k1", description: "x", ts: 0), Confirm(id: "k0", description: "y", ts: 0)],
            cloud: [], now: 10)
        XCTAssertEqual(items.map(\.id), ["confirm:k0", "confirm:k1", "question:s1", "session:claude:c1:a"])
    }

    func testCountAndHeadline() {
        let n = YourTurn.count(sessions: [sess("claude:c1:a", state: "needs_input", act: 1)],
                               notices: [notice("s1", ts: 2, tag: "rueckfrage:relay-ios:R1")],
                               requests: [req("r1", created: 3, expires: 50)], confirms: [Confirm(id: "k", description: "d")],
                               cloud: [cloud("c", state: "waiting", at: 4)], now: 10)
        XCTAssertEqual(n, 5)
        XCTAssertEqual(YourTurn.count(sessions: [], notices: [], requests: [], confirms: [], cloud: [], now: 10), 0)
        XCTAssertEqual(YourTurn.headline(0), "Nichts wartet auf dich.")
        XCTAssertEqual(YourTurn.headline(1), "1 wartet auf dich")
        XCTAssertEqual(YourTurn.headline(4), "4 warten auf dich")
        XCTAssertEqual(YourTurn.kindLabel(.question), "Rückfrage")
    }
}
