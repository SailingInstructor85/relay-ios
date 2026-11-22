import XCTest
@testable import RelayCore

final class TodayTests: XCTestCase {
    private func sess(_ key: String, state: String = "idle", act: Double = 0, asks: Bool = false, last: String = "", title: String = "",
                      extra: [String: JSON] = [:]) -> Session {
        var o: [String: JSON] = ["key": .string(key), "state": .string(state), "last_activity": .number(act), "asks": .bool(asks),
                                 "last_message": .string(last), "cwd": "/home/m/relay-ios", "title": .string(title.isEmpty ? "T " + key : title)]
        for (k, v) in extra { o[k] = v }
        return Session.from(.object(o))!
    }

    func testRowShowsModelContextStatusAndPreview() {
        let s = sess("claude:c1:a", state: "busy", act: 100, last: "Ich baue\n\n  gerade   den Tab.", title: "Relay Umbau",
                     extra: ["context": .object(["tokens": 130_000, "window": 200_000, "pct": 65, "level": "ok", "model": "claude-opus-5-5"])])
        let r = Today.row(s, unread: true, pinned: false)
        XCTAssertEqual(r.title, "Relay Umbau")
        XCTAssertEqual(r.meta, "opus 5.5 · 130k ctx")
        XCTAssertEqual(r.contextLevel, 0)
        XCTAssertEqual(r.status, .working)
        XCTAssertEqual(r.statusText, "◐ arbeitet")
        XCTAssertEqual(r.preview, "Ich baue gerade den Tab.")
        XCTAssertEqual(r.alias, "c1")
        XCTAssertEqual(r.folder, "relay-ios")
        XCTAssertTrue(r.unread)
    }

    func testWaitingRowShowsTheQuestion() {
        let s = sess("claude:c1:a", state: "needs_input", last: "letzte Nachricht",
                     extra: ["question": .object(["question": "Welche Variante\nsoll es sein?"])])
        let r = Today.row(s)
        XCTAssertEqual(r.status, .waits)
        XCTAssertEqual(r.statusText, "! wartet")
        XCTAssertEqual(r.preview, "Welche Variante soll es sein?")
        XCTAssertEqual(r.meta, "")
        let asking = Today.row(sess("claude:c1:b", state: "idle", asks: true, last: "zuletzt", extra: ["asks_text": "Soll ich pushen?"]))
        XCTAssertEqual(asking.status, .waits)
        XCTAssertEqual(asking.preview, "Soll ich pushen?")
        XCTAssertEqual(Today.row(sess("claude:c1:c")).statusText, "○ bereit")
    }

    func testContextLevels() {
        func ctx(_ level: String) -> SessionContext? { SessionContext.from(["tokens": 1000, "level": .string(level), "model": "claude-fable-5-2"]) }
        XCTAssertEqual(Today.contextLevel(nil), 0)
        XCTAssertEqual(Today.contextLevel(ctx("ok")), 0)
        XCTAssertEqual(Today.contextLevel(ctx("large")), 1)
        XCTAssertEqual(Today.contextLevel(ctx("full")), 2)
    }

    func testRowsOrderAndFilter() {
        let list = [
            sess("claude:c1:idle-old", act: 10),
            sess("claude:c1:idle-new", act: 90),
            sess("claude:c1:busy", state: "busy", act: 20),
            sess("claude:c1:wait", state: "needs_input", act: 5),
            sess("claude:c1:asks", act: 50, asks: true),
            sess("claude:c1:pinned", act: 1),
            sess("claude:c1:ended", state: "exited", act: 99),
            sess("claude:c1:closed", act: 99, extra: ["closed": true]),
            sess("claude:c1:sleeps", act: 99, extra: ["hibernated": true]),
            sess("claude:c1:bg", state: "busy", act: 99, extra: ["background": true]),
            sess("claude:c1:hidden", act: 99),
        ]
        let rows = Today.rows(list, unread: ["claude:c1:idle-old"], pinned: ["claude:c1:pinned"], hidden: ["claude:c1:hidden"])
        XCTAssertEqual(rows.map(\.key), ["claude:c1:asks", "claude:c1:wait", "claude:c1:busy", "claude:c1:pinned", "claude:c1:idle-new", "claude:c1:idle-old"])
        XCTAssertEqual(rows.last?.unread, true)
        XCTAssertEqual(Today.rows(list, limit: 2).map(\.key), ["claude:c1:asks", "claude:c1:wait"])
        XCTAssertEqual(Today.rows([]), [])
    }

    func testPill() {
        XCTAssertNil(Today.pill(waiting: 0, unread: 0))
        XCTAssertEqual(Today.pill(waiting: 1, unread: 5), Today.Pill(text: "1 braucht dich", urgent: true))
        XCTAssertEqual(Today.pill(waiting: 3, unread: 0), Today.Pill(text: "3 brauchen dich", urgent: true))
        XCTAssertEqual(Today.pill(waiting: 0, unread: 4), Today.Pill(text: "4 ungelesen", urgent: false))
    }

    func testNeedsCompact() {
        func item(_ n: Int) -> YourTurn.Item {
            YourTurn.Item(id: "question:s\(n)", kind: .question, since: Double(n), title: "Rückfrage R\(n) von vault", text: "Frage\n\(n)?",
                          target: .question(ref: "s\(n)", agent: "vault", quick: nil))
        }
        let all = (1...5).map(item)
        let n = Today.needs(all)
        XCTAssertEqual(n.shown.map(\.id), ["question:s1", "question:s2", "question:s3"])
        XCTAssertEqual(n.shown[0].label, "Rückfrage")
        XCTAssertEqual(n.shown[0].text, "Frage 1?")
        XCTAssertEqual(n.more, 2)
        XCTAssertEqual(Today.needs(Array(all.prefix(2))).more, 0)
        XCTAssertEqual(Today.needs([]).shown, [])
        XCTAssertEqual(Today.needsLink(more: 0), "In „Dein Zug“ beantworten")
        XCTAssertEqual(Today.needsLink(more: 1), "1 weiterer in „Dein Zug“")
        XCTAssertEqual(Today.needsLink(more: 2), "2 weitere in „Dein Zug“")
    }

    func testAssistantPreview() {
        XCTAssertEqual(Today.assistantPreview([]), Today.assistantHint)
        XCTAssertEqual(Today.assistantLast([]), 0)
        let turns = [JarvisTurn(q: "Was läuft?", a: "Zwei Sitzungen\narbeiten.", voice: false, ts: 10),
                     JarvisTurn(q: "Und sonst?", a: "", voice: true, ts: 20)]
        XCTAssertEqual(Today.assistantPreview(Array(turns.prefix(1))), "Zwei Sitzungen arbeiten.")
        XCTAssertEqual(Today.assistantPreview(turns), "Und sonst?")
        XCTAssertEqual(Today.assistantLast(turns), 20)
    }

    func testAgendaTime() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(Today.agendaTime(Today.AgendaItem(id: "1", title: "Termin", start: 9 * 3600 + 30 * 60), timeZone: utc), "09:30")
        XCTAssertEqual(Today.agendaTime(Today.AgendaItem(id: "2", title: "Urlaub", start: 0, allDay: true), timeZone: utc), "ganztägig")
    }
}
