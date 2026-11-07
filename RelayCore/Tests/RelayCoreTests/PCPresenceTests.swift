import XCTest
@testable import RelayCore

/// Anzeige „am PC offen“ (2026-11-07) und Sitzung am PC ohne tmux.
final class PCPresenceTests: XCTestCase {
    private func session(_ extra: String) -> Session {
        let base = #""key":"claude:c1:s1","tool":"claude","alias":"c1","id":"s1","cwd":"/home/u/p","title":"t","state":"idle","alive":true"#
        return Session.from(JSON.parse("{" + base + (extra.isEmpty ? "" : "," + extra) + "}")!)!
    }

    func testPresenceFromTheList() {
        XCTAssertEqual(PCPresence.of(session(#""attachable":true,"tmux_session":"c1-x-1","pc_attached":true"#)), .open)
        XCTAssertEqual(PCPresence.of(session(#""attachable":true,"tmux_session":"c1-x-1","pc_attached":false"#)), .closed)
        XCTAssertEqual(PCPresence.of(session(#""attachable":true,"tmux_session":"c1-x-1""#)), .unknown)  // älteres Gateway
        XCTAssertEqual(PCPresence.of(session(#""attachable":true,"tmux_session":"c1-x-1","pc_attached":true,"state":"exited","alive":false"#)), .closed)
        XCTAssertEqual(PCPresence.of(session(#""attachable":false,"tmux_session":null"#)), .open)  // Terminal ohne tmux
        XCTAssertEqual(PCPresence.of(session(#""attachable":false,"tmux_session":null,"pc_attached":true"#)), .open)
    }

    func testDeskTerminal() {
        XCTAssertTrue(DeskTerminal.isDeskTerminal(session(#""attachable":false,"tmux_session":null"#)))
        XCTAssertFalse(DeskTerminal.isDeskTerminal(session(#""attachable":true,"tmux_session":"c1-x-1""#)))
        XCTAssertFalse(DeskTerminal.isDeskTerminal(session(#""attachable":true,"tmux_session":null"#)))  // claude --bg
        XCTAssertFalse(DeskTerminal.isDeskTerminal(session(#""attachable":false,"tmux_session":null,"background":true"#)))
        XCTAssertFalse(DeskTerminal.isDeskTerminal(session(#""attachable":false,"tmux_session":null,"alive":false,"state":"exited""#)))
        XCTAssertTrue(DeskTerminal.isRefusal("this session is open in a Desktop terminal outside tmux: reply there"))
        XCTAssertFalse(DeskTerminal.isRefusal("session is busy"))
    }

    func testMonitorEventsKeepTheMark() {
        let listed = session(#""attachable":true,"tmux_session":"c1-x-1","pc_attached":true"#)
        let fromEvent = session(#""attachable":true,"tmux_session":"c1-x-1","state":"busy""#)
        XCTAssertEqual(fromEvent.keepingPC(from: listed).pcAttached, true)
        XCTAssertEqual(fromEvent.keepingPC(from: nil).pcAttached, nil)
        let explicit = session(#""attachable":true,"tmux_session":"c1-x-1","pc_attached":false"#)
        XCTAssertEqual(explicit.keepingPC(from: listed).pcAttached, false)  // die Liste weiß es neuer
        let other = Session.from(JSON.parse(#"{"key":"claude:c1:s2","alive":true}"#)!)!
        XCTAssertNil(fromEvent.keepingPC(from: other).pcAttached)  // andere Sitzung
    }

    func testEventUpdatesTheList() {
        var list = ["claude:c1:s1": session(#""attachable":true,"tmux_session":"c1-x-1","pc_attached":true"#)]
        XCTAssertTrue(PCPresence.apply(JSON.parse(#"{"type":"pc_attached","session_key":"claude:c1:s1","pc_attached":false}"#)!, to: &list))
        XCTAssertEqual(PCPresence.of(list["claude:c1:s1"]!), .closed)
        XCTAssertFalse(PCPresence.apply(JSON.parse(#"{"type":"pc_attached","session_key":"claude:c1:s1","pc_attached":false}"#)!, to: &list))
        XCTAssertFalse(PCPresence.apply(JSON.parse(#"{"type":"pc_attached","session_key":"claude:c1:nope","pc_attached":true}"#)!, to: &list))
        XCTAssertTrue(PCPresence.apply(JSON.parse(#"{"type":"pc_attached","session_key":"claude:c1:s1","pc_attached":true}"#)!, to: &list))
        XCTAssertEqual(PCPresence.of(list["claude:c1:s1"]!), .open)
    }
}
