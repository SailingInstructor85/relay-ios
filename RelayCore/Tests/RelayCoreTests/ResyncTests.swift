import XCTest
@testable import RelayCore

/// Nachladen nach dem Wiederverbinden, Halten der Verbindung im Hintergrund und abgelehnte Nachrichten (2026-11-12,
/// „Antwort des Agenten kommt in der App nicht an“).
final class ResyncTests: XCTestCase {
    private func m(_ id: String, _ text: String = "t", role: String = "assistant") -> TMessage {
        TMessage(id: id, role: role, text: text, tools: [], ts: 0, files: [])
    }

    private func session(state: String = "idle", alive: Bool = true, tmux: String? = "c1-x-1", attachable: Bool = true,
                         background: Bool = false, key: String = "claude:c1:s1") -> Session {
        Session.from(.obj(["key": .string(key), "tool": .string("claude"), "state": .string(state), "alive": .bool(alive),
                           "attachable": .bool(attachable), "tmux_session": tmux.map { .string($0) },
                           "background": .bool(background), "title": .string("T")]))!
    }

    // MARK: Verlauf

    func testMissedReplyIsAppended() {
        // 11.11.2026: die Frage steht im Chat, die Antworten kamen, während die Verbindung getrennt war
        let old = [m("1", role: "user"), m("2"), m("3", role: "user")]
        let r = TranscriptSync.merge(old, latest: old + [m("4"), m("5")])
        XCTAssertEqual(r.messages.map(\.id), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(r.added, 2)
        XCTAssertFalse(r.replaced)
    }

    func testKnownMessageTakesTheNewText() {
        let r = TranscriptSync.merge([m("1"), m("2", "halb")], latest: [m("1"), m("2", "halb und ganz")])
        XCTAssertEqual(r.messages.last?.text, "halb und ganz")
        XCTAssertEqual(r.added, 0)
        XCTAssertFalse(r.replaced)
    }

    func testOlderPagesStay() {
        // „Ältere Nachrichten laden“ hat 1 und 2 geholt; die neueste Seite beginnt bei 3
        let r = TranscriptSync.merge([m("1"), m("2"), m("3"), m("4")], latest: [m("3"), m("4"), m("5")])
        XCTAssertEqual(r.messages.map(\.id), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(r.added, 1)
        XCTAssertFalse(r.replaced)
    }

    func testNoOverlapShowsTheNewPageAlone() {
        // mehr als eine Seite verpasst: lieber die neue Seite allein als eine Lücke
        let r = TranscriptSync.merge([m("1"), m("2")], latest: [m("60"), m("61")])
        XCTAssertEqual(r.messages.map(\.id), ["60", "61"])
        XCTAssertEqual(r.added, 2)
        XCTAssertTrue(r.replaced)
    }

    func testEmptyCases() {
        XCTAssertEqual(TranscriptSync.merge([], latest: [m("1")]), .init(messages: [m("1")], added: 1, replaced: true))
        XCTAssertEqual(TranscriptSync.merge([m("1")], latest: []), .init(messages: [m("1")], added: 0, replaced: false))
    }

    func testListThatStartedLaterTakesThePageStart() {
        // der Chat kannte nur das Ende (Live-Anhänge); die Seite reicht weiter zurück und bringt ihr `before` mit
        let r = TranscriptSync.merge([m("4"), m("5")], latest: [m("3"), m("4"), m("5"), m("6")])
        XCTAssertEqual(r.messages.map(\.id), ["3", "4", "5", "6"])
        XCTAssertEqual(r.added, 2)
        XCTAssertTrue(r.replaced)
    }

    // MARK: Verbindung im Hintergrund halten

    func testLingerOnlyWhileSomethingWorks() {
        XCTAssertFalse(BackgroundLinger.wanted([session()]))
        XCTAssertTrue(BackgroundLinger.wanted([session(), session(state: "busy")]))
        XCTAssertFalse(BackgroundLinger.wanted([session(state: "busy", background: true)]))  // Hintergrundlauf
        XCTAssertFalse(BackgroundLinger.wanted([session(state: "exited", alive: false)]))
        let busy = [session(state: "busy")]
        XCTAssertFalse(BackgroundLinger.done(busy, elapsed: 5, foreground: false, connected: true))
        XCTAssertTrue(BackgroundLinger.done(busy, elapsed: 5, foreground: true, connected: true))
        XCTAssertTrue(BackgroundLinger.done(busy, elapsed: 5, foreground: false, connected: false))
        XCTAssertTrue(BackgroundLinger.done(busy, elapsed: BackgroundLinger.maxSeconds, foreground: false, connected: true))
        XCTAssertTrue(BackgroundLinger.done([session()], elapsed: 5, foreground: false, connected: true))  // fertig geworden
    }

    // MARK: abgelehnte Nachrichten

    private let busyMsg = "session is busy"
    private let deskMsg = "this session is open in a Desktop terminal outside tmux: reply there, or close it there and send again from the phone (it then resumes here)"

    private func refused(_ error: String, at: Double = 1000, id: String = "1") -> OutItem {
        OutItem(id: id, key: "claude:c1:s1", text: "hallo", at: at, state: .failed, error: error)
    }

    func testBusyRefusalGoesOutOnceTheSessionIsIdle() {
        let i = refused(busyMsg)
        XCTAssertTrue(OutboxLogic.waitsForSession(i, now: 1010))
        XCTAssertFalse(OutboxLogic.resendable(i, session: session(state: "busy"), now: 1010))
        XCTAssertFalse(OutboxLogic.resendable(i, session: session(state: "needs_input"), now: 1010))  // eine Auswahl ist offen
        XCTAssertFalse(OutboxLogic.resendable(i, session: nil, now: 1010))
        XCTAssertFalse(OutboxLogic.resendable(i, session: session(state: "exited", alive: false), now: 1010))
        XCTAssertTrue(OutboxLogic.resendable(i, session: session(), now: 1010))
    }

    func testDeskRefusalGoesOutOnceTheSessionRunsInTmux() {
        let i = refused(deskMsg)
        let desk = session(tmux: nil, attachable: false)
        XCTAssertTrue(DeskTerminal.isDeskTerminal(desk))
        XCTAssertFalse(OutboxLogic.resendable(i, session: desk, now: 1010))
        XCTAssertTrue(OutboxLogic.resendable(i, session: session(), now: 1010))  // am PC mit claude --resume neu geöffnet
        // eine „arbeitet“-Absage geht nicht in eine Sitzung ohne tmux (die würde nur wieder ablehnen)
        XCTAssertFalse(OutboxLogic.resendable(refused(busyMsg), session: desk, now: 1010))
    }

    func testOldOrOtherRefusalsStay() {
        let late = 1000 + OutboxLogic.autoResendWindow + 1
        XCTAssertFalse(OutboxLogic.waitsForSession(refused(busyMsg), now: late))
        XCTAssertFalse(OutboxLogic.resendable(refused(busyMsg), session: session(), now: late))
        XCTAssertFalse(OutboxLogic.waitsForSession(refused("unknown session"), now: 1010))
        XCTAssertFalse(OutboxLogic.waitsForSession(refused("typed but still in the input field"), now: 1010))  // nie doppelt tippen
        let queued = OutItem(id: "2", key: "k", text: "x", at: 1000)
        XCTAssertFalse(OutboxLogic.waitsForSession(queued, now: 1010))
    }

    func testStatusSaysThatItWaits() {
        let busy = refused(busyMsg), desk = refused(deskMsg)
        XCTAssertEqual(OutboxLogic.status(busy, connected: true, network: true), "Nicht gesendet: die Sitzung arbeitet gerade")
        XCTAssertEqual(OutboxLogic.status(busy, connected: true, network: true, now: 1010),
                       "Wartet: die Sitzung arbeitet gerade. Geht von selbst hinaus, sobald sie fertig ist")
        XCTAssertTrue(OutboxLogic.status(desk, connected: true, network: true, now: 1010).hasPrefix("Wartet: die Sitzung ist am PC in einem Terminal ohne tmux offen"))
        let late = 1000 + OutboxLogic.autoResendWindow + 1
        XCTAssertEqual(OutboxLogic.status(desk, connected: true, network: true, now: late), DeskTerminal.statusText)
    }

    func testListNote() {
        XCTAssertNil(OutboxLogic.listNote([], now: 1010))
        XCTAssertNil(OutboxLogic.listNote([OutItem(id: "d", key: "k", text: "x", at: 1000, state: .delivered)], now: 1010))
        XCTAssertEqual(OutboxLogic.listNote([refused(busyMsg)], now: 1010), "1 Nachricht wartet auf die Sitzung")
        XCTAssertEqual(OutboxLogic.listNote([refused(busyMsg), refused(deskMsg, id: "2")], now: 1010), "2 Nachrichten warten auf die Sitzung")
        XCTAssertEqual(OutboxLogic.listNote([refused(busyMsg), refused("unknown session", id: "2")], now: 1010), "2 Nachrichten nicht gesendet")
        let late = 1000 + OutboxLogic.autoResendWindow + 1
        XCTAssertEqual(OutboxLogic.listNote([refused(busyMsg)], now: late), "1 Nachricht nicht gesendet")
        XCTAssertEqual(OutboxLogic.listNote([OutItem(id: "q", key: "k", text: "x", at: 1000)], now: 1010), "1 Nachricht im Postausgang")
    }
}
