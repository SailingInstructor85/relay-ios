import XCTest
@testable import RelayCore

/// Anzeige „am PC offen“ (2026-11-07) und Sitzung am PC ohne tmux.
final class PCPresenceTests: XCTestCase {
    /// Grundzeile einer lebenden Sitzung; Schlüssel aus `extra` ersetzen die der Grundzeile (ein JSON-Text mit doppelten
    /// Schlüsseln liefert auf Linux den ersten Wert, darum werden die Objekte zusammengeführt statt verkettet).
    private func session(_ extra: String) -> Session {
        let base = #"{"key":"claude:c1:s1","tool":"claude","alias":"c1","id":"s1","cwd":"/home/u/p","title":"t","state":"idle","alive":true}"#
        guard case .object(let b) = JSON.parse(base)!, case .object(let e) = JSON.parse("{" + extra + "}")! else { fatalError("Testdaten") }
        return Session.from(.object(b.merging(e) { $1 }))!
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
        // Hinweis über der Eingabe: nur mitlesen, dazu der Befehl für den PC (seit 0.3.16 statt des Umzugsknopfs)
        let desk = session(#""attachable":false,"tmux_session":null"#)
        XCTAssertEqual(DeskTerminal.resumeCommand(desk), "claude --resume \(desk.sid)")
        XCTAssertTrue(DeskTerminal.hint(desk).hasPrefix("Am PC in einem Terminal ohne tmux offen: vom Handy nur mitlesen."))
        XCTAssertTrue(DeskTerminal.hint(desk).contains("claude --resume \(desk.sid)"))
        XCTAssertTrue(DeskTerminal.hint(desk).contains("dann geht es in tmux weiter"))
        let codex = Session.from(JSON.parse(Data(#"{"key":"codex:x1:abc","alive":true,"state":"idle","attachable":false,"tmux_session":null}"#.utf8))!)!
        XCTAssertNil(DeskTerminal.resumeCommand(codex))
        XCTAssertFalse(DeskTerminal.hint(codex).contains("--resume"))
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

final class SubmitCheckTests: XCTestCase {
    func testStuckMessageFromGateway() {
        let m = "not sent: the text is still in the input field at the PC (Enter did not go through)"
        XCTAssertTrue(SubmitCheck.isStuck(m))
        XCTAssertFalse(SubmitCheck.isStuck("session is busy"))
        XCTAssertEqual(SubmitCheck.display(m), SubmitCheck.short)
        XCTAssertEqual(SubmitCheck.display("tmux pane %3 no longer exists"), "tmux pane %3 no longer exists")
        XCTAssertFalse(SubmitCheck.text.contains("—"))
        let item = OutItem(id: "1", key: "k", text: "hallo", at: 0, state: .failed, error: m)
        XCTAssertEqual(OutboxLogic.status(item, connected: true, network: true), "Nicht abgeschickt: " + SubmitCheck.short)
        let row = WindDown.Item(key: "k", title: "A", phase: .error, detail: m)
        XCTAssertEqual(row.statusLine, "Fehler, bleibt offen · " + SubmitCheck.short)
    }
}
