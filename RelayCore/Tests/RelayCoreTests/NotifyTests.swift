import XCTest
@testable import RelayCore

final class NotifyTests: XCTestCase {
    func testOrder() {
        var p = NotifyPrefs()
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: true), .none)
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, ev: StateInfo(quiet: true)), .none)
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false), .popup)
        p.ready = "silent"
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false), .silent)
        p.ready = "off"
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false), .none)
        XCTAssertEqual(NotifyPolicy.alert(.needsInput, p, muted: false), .popup)
        p.input = "silent"
        XCTAssertEqual(NotifyPolicy.alert(.needsInput, p, muted: false), .silent)
        XCTAssertEqual(NotifyPolicy.alert(.ended, NotifyPrefs(), muted: false), .popup)
    }

    func testDesk() {
        var p = NotifyPrefs()
        let desk = StateInfo(desk: true)
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, ev: desk), .silent)
        XCTAssertEqual(NotifyPolicy.alert(.needsInput, p, muted: false, ev: desk), .silent)
        p.quietAtDesk = false
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, ev: desk), .popup)
    }

    func testAuto() {
        var p = NotifyPrefs()
        let withTasks = StateInfo(origin: "auto", tasks: 2)
        let noTasks = StateInfo(origin: "auto", tasks: 0)
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, ev: withTasks), .silent)
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, ev: noTasks), .popup)
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, ev: StateInfo(asks: true, origin: "auto", tasks: 2)), .popup)
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, ev: StateInfo(origin: "user", tasks: 2)), .popup)
        p.auto = "silent"
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, ev: noTasks), .silent)
        p.auto = "same"
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, ev: withTasks), .popup)
        // a question that arrives in an auto turn is not touched
        p.auto = "silent"
        XCTAssertEqual(NotifyPolicy.alert(.needsInput, p, muted: false, ev: noTasks), .popup)
    }

    func testQuietHours() {
        var p = NotifyPrefs()
        p.quietHours = true
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, minuteOfDay: 23 * 60), .silent)
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, minuteOfDay: 3 * 60), .silent)
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, minuteOfDay: 12 * 60), .popup)
        XCTAssertEqual(NotifyPolicy.alert(.ended, p, muted: false, minuteOfDay: 23 * 60), .silent)
        XCTAssertEqual(NotifyPolicy.alert(.needsInput, p, muted: false, minuteOfDay: 23 * 60), .popup)
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, ev: StateInfo(asks: true), minuteOfDay: 23 * 60), .popup)
        XCTAssertTrue(QuietHours.within(22 * 60, 7 * 60, 22 * 60))
        XCTAssertFalse(QuietHours.within(22 * 60, 7 * 60, 7 * 60))
        XCTAssertTrue(QuietHours.within(8 * 60, 9 * 60, 8 * 60 + 30))
        XCTAssertFalse(QuietHours.within(8 * 60, 9 * 60, 9 * 60))
        XCTAssertFalse(QuietHours.within(600, 600, 600))
        XCTAssertEqual(QuietHours.label(7 * 60 + 5), "07:05")
        p.quietHours = false
        XCTAssertEqual(NotifyPolicy.alert(.ready, p, muted: false, minuteOfDay: 23 * 60), .popup)
    }

    func testNotices() {
        XCTAssertTrue(NoticeLogic.show(ts: 0, now: 1_000_000))
        XCTAssertTrue(NoticeLogic.show(ts: 1_000_000 - 3600, now: 1_000_000))
        XCTAssertFalse(NoticeLogic.show(ts: 1_000_000 - 90_000, now: 1_000_000))
        XCTAssertEqual(NoticeLogic.slot(tag: "checkin", seq: 5), "notice:checkin")
        XCTAssertEqual(NoticeLogic.slot(tag: nil, seq: 5), "notice#5")
        XCTAssertEqual(NoticeLogic.slot(tag: " ", seq: 5), "notice#5")
    }

    func testMerge() {
        let now = 10_000_000.0
        func n(_ r: String, _ ts: Double) -> Notice { Notice(ref: r, ts: ts, title: r, text: "", source: "") }
        var l: [Notice] = []
        l = NoticeLogic.merge(l, n("a", now - 100), now: now)
        l = NoticeLogic.merge(l, n("b", now - 50), now: now)
        l = NoticeLogic.merge(l, n("a", now - 10), now: now)
        XCTAssertEqual(l.map(\.ref), ["a", "b"])
        l = NoticeLogic.merge(l, n("old", now - 15 * 86_400), now: now)
        XCTAssertEqual(l.map(\.ref), ["a", "b"])
        for i in 0..<120 { l = NoticeLogic.merge(l, n("x\(i)", now - Double(i)), now: now) }
        XCTAssertEqual(l.count, 100)
        let again = NoticeLogic.decode(NoticeLogic.encode(Array(l.prefix(3))))
        XCTAssertEqual(again, Array(l.prefix(3)))
    }

    func testNoticeEvent() {
        let ev = JSON.object(["type": "notice", "seq": 7, "ts": 123.0, "title": "T", "text": "x", "source": "backup", "tag": "bk"])
        let n = Notice.from(event: ev, now: 999)
        XCTAssertEqual(n.ref, "s7"); XCTAssertEqual(n.ts, 123); XCTAssertEqual(n.tag, "bk")
        XCTAssertEqual(Notice.from(event: ["title": "x"], now: 5).ref, "l5000")
    }

    func testLines() {
        let t = "Preis gefallen: [Kopfhörer](https://www.amazon.de/dp/1)\nMehr unter https://example.com/a, bitte\nkein Link\n\nNur https://x.org/p"
        let l = NoticeLogic.lines(t)
        XCTAssertEqual(l[0], NoticeLogic.Line(text: "Preis gefallen: Kopfhörer", links: ["https://www.amazon.de/dp/1"]))
        XCTAssertEqual(l[1].links.count, 1)
        XCTAssertTrue(l[1].links[0].hasPrefix("https://example.com/a"))
        XCTAssertTrue(l[1].text.hasPrefix("Mehr unter"))
        XCTAssertEqual(l[2], NoticeLogic.Line(text: "kein Link", links: []))
        XCTAssertEqual(l[3], NoticeLogic.Line(text: "", links: []))
        XCTAssertEqual(l[4].text, "Nur")
        XCTAssertEqual(NoticeLogic.web("www.x.de"), "https://www.x.de")
        XCTAssertNil(NoticeLogic.web("/etc/hosts"))
        XCTAssertNil(NoticeLogic.web("mailto:a@b.de"))
        XCTAssertEqual(NoticeLogic.host("https://www.amazon.de/dp/1?x=1"), "amazon.de")
        XCTAssertEqual(NoticeLogic.host("http://a.b:8080/x"), "a.b")
        XCTAssertEqual(NoticeLogic.lines("https://www.x.de/p")[0].text, "x.de")
    }

    func testGoto() {
        func n(_ tag: String?) -> Notice { Notice(ref: "r", ts: 0, title: "", text: "", source: "", tag: tag) }
        XCTAssertEqual(NoticeLogic.goto(n("quota-claude")), .accounts)
        XCTAssertEqual(NoticeLogic.goto(n("digest")), .sessions)
        XCTAssertEqual(NoticeLogic.goto(n("jarvis")), .jarvis)
        XCTAssertEqual(NoticeLogic.goto(n(nil)), .none)
        XCTAssertEqual(NoticeLogic.goto(n("price")), .none)
    }

    func testSendRequests() {
        let ev = JSON.object(["request_id": "r1", "kind": "mail", "executor": "desktop", "text": "Hallo", "summary": "Mail an Anna",
                              "requested_by": "claude", "expires_at": 2000.0, "ts": 1000.0])
        let r = SendReq.from(event: ev)!
        XCTAssertEqual(r.createdAt, 1000)
        XCTAssertTrue(SendRules.accept(now: 1500, r, pending: [], handled: []))
        XCTAssertFalse(SendRules.accept(now: 2500, r, pending: [], handled: []))
        XCTAssertFalse(SendRules.accept(now: 1500, r, pending: ["r1"], handled: []))
        XCTAssertFalse(SendRules.accept(now: 1500, r, pending: [], handled: ["r1"]))
        var phone = r; phone.executor = "phone"
        XCTAssertFalse(SendRules.accept(now: 1500, phone, pending: [], handled: []))
        XCTAssertEqual(SendRules.title(r), "E-Mail freigeben?")
        XCTAssertEqual(SendRules.body(r), "Mail an Anna\n\nHallo")
        var same = r; same.summary = "Hallo"
        XCTAssertEqual(SendRules.body(same), "Hallo")
        XCTAssertEqual(SendReq.from(event: r.json()), r)
        XCTAssertNil(SendReq.from(event: ["kind": "mail"]))
    }

    func testGroups() {
        func req(_ id: String, _ text: String, _ created: Double) -> SendReq {
            SendReq(id: id, kind: "mail", executor: "desktop", app: "", conversation: "", text: text, summary: "s", requestedBy: "c", expiresAt: 5000, createdAt: created)
        }
        let g = SendRules.groups([req("a", "x", 10), req("b", "y", 30), req("c", "x", 20)])
        XCTAssertEqual(g.map { $0.map(\.id) }, [["b"], ["c", "a"]])
        XCTAssertEqual(SendRules.stripText(groups: 1, confirms: 0, first: "Mail an Anna"), "Freigeben? Mail an Anna")
        XCTAssertEqual(SendRules.stripText(groups: 2, confirms: 1, first: "x"), "3 Freigaben warten")
        XCTAssertEqual(SendRules.stripText(groups: 0, confirms: 0, first: nil), "")
        XCTAssertTrue(ConfirmRules.fresh(ts: 1000, now: 1000 + 600))
        XCTAssertFalse(ConfirmRules.fresh(ts: 1000, now: 1000 + 3600))
    }

    func testAgentQuestion() {
        XCTAssertEqual(Rueckfrage.parse(tag: "rueckfrage:relay-ios:R1")?.agent, "relay-ios")
        XCTAssertEqual(Rueckfrage.parse(tag: "rueckfrage:relay-ios:r12")?.id, "R12")
        XCTAssertEqual(Rueckfrage.parse(tag: "meldung:stellen:M2")?.id, "M2")
        XCTAssertNil(Rueckfrage.parse(tag: "rueckfrage:relay-ios:M2"))
        XCTAssertNil(Rueckfrage.parse(tag: "rueckfrage:relay-ios:Rx"))
        XCTAssertNil(Rueckfrage.parse(tag: "backup"))
        XCTAssertNil(Rueckfrage.parse(tag: nil))

        let n = Notice(ref: "s7", ts: 1, title: "Rückfrage R1 · relay-ios",
                       text: "Soll ich die alte Route löschen?\nKontext: Seit 2024 ungenutzt.\nEmpfehlung: ja",
                       source: "relay-ios", tag: "rueckfrage:relay-ios:R1")
        let q = Rueckfrage.question(n)
        XCTAssertEqual(q, AgentQuestion(agent: "relay-ios", id: "R1", question: "Soll ich die alte Route löschen?",
                                        context: "Seit 2024 ungenutzt.", recommendation: "ja"))
        XCTAssertEqual(Rueckfrage.quickAnswer(q!), "ja")
        XCTAssertEqual(Rueckfrage.category(q!), "rueckfrage-ja")
        XCTAssertEqual(Rueckfrage.title(q!), "Rückfrage R1 von relay-ios")

        let plain = Notice(ref: "s8", ts: 1, title: "", text: "Weiter mit Plan B?", source: "", tag: "rueckfrage:a:R2")
        let p = Rueckfrage.question(plain)!
        XCTAssertEqual(p.question, "Weiter mit Plan B?"); XCTAssertEqual(p.recommendation, "")
        XCTAssertNil(Rueckfrage.quickAnswer(p)); XCTAssertEqual(Rueckfrage.category(p), "rueckfrage")

        let m = Rueckfrage.question(Notice(ref: "s9", ts: 1, title: "Fertig", text: "", source: "", tag: "meldung:a:M1"))!
        XCTAssertFalse(m.wantsAnswer); XCTAssertEqual(m.question, "Fertig"); XCTAssertNil(Rueckfrage.category(m))
        XCTAssertNil(Rueckfrage.question(Notice(ref: "s1", ts: 1, title: "", text: "", source: "", tag: "backup")))

        let item = Rueckfrage.answerItem(agent: "relay-ios", id: "R1", answer: "ja", now: 1700000000.5)
        XCTAssertEqual(item.str("id"), "rueckfrage|relay-ios|R1|1700000000500")
        XCTAssertEqual(item.str("app"), "rueckfrage"); XCTAssertEqual(item.str("text"), "ja")
        XCTAssertEqual(item.num("ts"), 1700000000.5, accuracy: 0.001)

        // the answer survives a replay of the same notice and the round trip to disk
        var answered = n; answered.answer = "ja"
        let kept = NoticeLogic.merge([answered], n, now: 2)
        XCTAssertEqual(kept.first?.answer, "ja")
        XCTAssertEqual(NoticeLogic.decode(NoticeLogic.encode(kept)).first?.answer, "ja")
        XCTAssertNil(NoticeLogic.decode(NoticeLogic.encode([n])).first?.answer)
    }
}
