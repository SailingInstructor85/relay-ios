import XCTest
@testable import RelayCore

final class RelayCoreTests: XCTestCase {
    func fixture(_ name: String) throws -> JSON {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try XCTUnwrap(JSON.parse(try Data(contentsOf: url)))
    }

    func testJSONRoundTrip() {
        let o: JSON = ["type": "rpc", "id": "abc", "params": ["n": 3, "x": 1.5, "b": true, "l": ["a"]]]
        let back = JSON.parse(o.serialized())
        XCTAssertEqual(back, o)
        XCTAssertTrue(o.serialized().contains("\"n\":3"), o.serialized())
        XCTAssertEqual(back?["params"]["b"].bool, true)
    }

    func testSessionParsing() {
        let line = #"{"key":"claude:c2:4f1c","tool":"claude","alias":"c2","id":"4f1c","cwd":"/home/dev/webapp/","title":"fix bench","state":"idle","alive":true,"attachable":true,"tmux_session":"c2-webapp-3fa1","last_activity":1759676400.5,"last_message":"Done","asks":true,"asks_text":"1. Soll ich?","question":{"question":"Which?","header":"T","options":[{"label":"A","description":"a"}],"multi":false,"count":1},"context":{"tokens":412000,"window":1000000,"pct":41,"level":"large","model":"claude-opus-5-5"}}"#
        let s = Session.from(JSON.parse(line)!)!
        XCTAssertEqual(s.folder, "webapp")
        XCTAssertEqual(s.target, "tmux:c2-webapp-3fa1")
        XCTAssertTrue(s.waits)
        XCTAssertEqual(s.shownState, "needs_input")
        XCTAssertEqual(s.question?.options.first?.label, "A")
        XCTAssertEqual(s.context?.label, "opus 5.5 · 412k ctx")
        XCTAssertTrue(s.matches("claude:c2:tmux-c2-webapp-3fa1"))
        var ended = s; ended.state = "exited"
        XCTAssertEqual(ended.target, "claude:c2:4f1c")
    }

    func testSessionKeyFallback() {
        let s = Session.from(["key": "codex:x1:abc:def"])!
        XCTAssertEqual(s.tool, "codex"); XCTAssertEqual(s.alias, "x1"); XCTAssertEqual(s.sid, "abc:def")
    }

    func testModelPicker() throws {
        let m = try XCTUnwrap(ScreenMenu.from(try fixture("model")))
        XCTAssertEqual(m.kind, "picker")
        XCTAssertFalse(m.options.isEmpty)
        XCTAssertNotNil(m.cursorIndex)
        let steps = m.stepsToPick(0)
        XCTAssertFalse(steps.isEmpty)
    }

    func testMultiQuestion() throws {
        let m = try XCTUnwrap(ScreenMenu.from(try fixture("question-multi")))
        XCTAssertTrue(m.multi)
        XCTAssertTrue(m.options.contains { $0.checked != nil })
    }

    func testPermissionPrompt() throws {
        let m = try XCTUnwrap(ScreenMenu.from(try fixture("permission-prompt")))
        XCTAssertEqual(m.kind, "picker")
        XCTAssertEqual(m.stepsToPick(0), ["1"])
    }

    func testPanel() throws {
        let m = try XCTUnwrap(ScreenMenu.from(try fixture("v308-usage")))
        XCTAssertTrue(m.isPanel)
        XCTAssertFalse(m.blocks.isEmpty)
        XCTAssertGreaterThanOrEqual(m.tabs.count, 3)
    }

    func testArrowSteps() {
        let opts = (1...4).map { MenuOption(label: "o\($0)", description: "", n: nil, current: false, checked: nil, input: false) }
        let m = ScreenMenu(id: "x", kind: "list", title: "", text: "", options: opts, cursor: 1, scrolls: false, multi: false, digits: true,
                     body: "", box: "", footer: "", plan: "", actions: [], blocks: [], tabs: [], nav: false, otherN: nil, submit: nil)
        XCTAssertEqual(m.stepsToPick(2), ["Down", "Down", "Enter"])
        XCTAssertEqual(m.stepsToPick(0), ["Enter"])
    }

    func testStripANSI() {
        XCTAssertEqual(TermText.stripANSI("\u{1B}[1;32mok\u{1B}[0m \u{1B}]0;title\u{07}x"), "ok x")
    }

    func testIdentity() throws {
        let id = Identity()
        let again = try Identity(rawSeed: id.rawSeed)
        XCTAssertEqual(id.openSSHPublicKey(), again.openSSHPublicKey())
        let pub = id.openSSHPublicKey()
        XCTAssertTrue(pub.hasPrefix("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI"), pub)
        XCTAssertTrue(HostKeys.fingerprint(pub).hasPrefix("SHA256:"))
    }

    func testHello() {
        let h = Hello.make(sinceSeq: 12, pinned: ["b", "a"], appVersion: "t")
        XCTAssertEqual(h["since_seq"].int, 12)
        XCTAssertEqual(h["pinned"].array.compactMap(\.string), ["a", "b"])
        XCTAssertEqual(h["version"].int, 2)
    }
}
