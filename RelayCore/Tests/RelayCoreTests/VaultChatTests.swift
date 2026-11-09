import XCTest
@testable import RelayCore

final class VaultChatTests: XCTestCase {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    // 2026-11-09 15:42 in Berlin (UTC+1)
    let at: Double = 1_794_235_320

    func testBatchKeepsOrderAndSkipsOthers() {
        let a = OutItem(id: "a", key: VaultChat.key, text: "eins", at: 1, state: .sending)
        let b = OutItem(id: "b", key: "claude:x", text: "andere Sitzung", at: 2)
        let c = OutItem(id: "c", key: VaultChat.key, text: "zwei", at: 3)
        let d = OutItem(id: "d", key: VaultChat.key, text: "kaputt", at: 4, state: .failed)
        let e = OutItem(id: "e", key: VaultChat.key, text: "drei", at: 5)
        XCTAssertEqual(VaultChat.batch([a, b, c, d, e], next: a).map(\.id), ["a", "c", "e"])
    }

    func testLaunchedFoundByTag() {
        let tag = VaultChat.tag("3FA9-C2D1-0000")
        XCTAssertEqual(tag, "3fa9c2")
        let s = [(key: "claude:c1:1", name: "Vault"), (key: "claude:c1:2", name: "Vom iPhone 3fa9c2")]
        XCTAssertEqual(VaultChat.launched(s, tag: tag), "claude:c1:2")
        XCTAssertNil(VaultChat.launched(s, tag: "ffffff"))
        XCTAssertNil(VaultChat.launched(s, tag: ""))
    }

    func testReusable() {
        XCTAssertTrue(VaultChat.reusable(alive: true, closed: false, hibernated: false))
        XCTAssertFalse(VaultChat.reusable(alive: false, closed: false, hibernated: false))
        XCTAssertFalse(VaultChat.reusable(alive: true, closed: true, hibernated: false))
        XCTAssertFalse(VaultChat.reusable(alive: true, closed: false, hibernated: true))
    }

    func testStoredNames() {
        let n = VaultChat.storedName(id: "AB12-cd34-ef", name: "foto 1.jpg")
        XCTAssertEqual(n, "ab12cd34-foto 1.jpg")
        XCTAssertEqual(VaultChat.displayName(n), "foto 1.jpg")
        XCTAssertEqual(VaultChat.displayName(VaultChat.storedName(id: "x", name: "a/b.pdf")), "a_b.pdf")
        XCTAssertEqual(VaultChat.displayName("ohne-prefix.pdf"), "ohne-prefix.pdf")
    }

    func testBody() {
        XCTAssertEqual(VaultChat.body(" Notiz ", paths: []), "Notiz")
        XCTAssertEqual(VaultChat.body("Notiz", paths: ["/up/a.jpg"]), "Notiz\nAnhang: /up/a.jpg")
        XCTAssertEqual(VaultChat.body("", paths: ["/up/a.jpg", "/up/b.pdf"]), "Anhang: /up/a.jpg\nAnhang: /up/b.pdf")
    }

    func testPrompt() {
        let one = VaultChat.prompt([(at: at, text: "Milch kaufen")], timeZone: berlin)
        XCTAssertTrue(one.hasPrefix("Nachricht vom iPhone (Vault-Chat in Relay, geschrieben 09.11. 15:42):\n\nMilch kaufen\n"))
        XCTAssertTrue(one.contains("AGENTS.md"))
        let two = VaultChat.prompt([(at: at, text: "eins"), (at: at + 60, text: "zwei")], timeZone: berlin)
        XCTAssertTrue(two.hasPrefix("2 Nachrichten vom iPhone"))
        let r1 = two.range(of: "1. (09.11. 15:42)\neins")!, r2 = two.range(of: "2. (09.11. 15:43)\nzwei")!
        XCTAssertLessThan(r1.lowerBound, r2.lowerBound)
        XCTAssertEqual(VaultChat.followUp("noch was", at: at, timeZone: berlin), "Nachricht vom iPhone (Vault-Chat, 09.11. 15:42):\nnoch was")
    }

    func testOutItemFilesRoundTrip() {
        let i = OutItem(id: "f", key: VaultChat.key, text: "", at: 1, files: ["ab12cd34-foto.jpg"])
        let back = OutboxLogic.decode(OutboxLogic.encode([i]))
        XCTAssertEqual(back, [i])
        XCTAssertEqual(OutboxLogic.retried(i, force: nil, newId: "g").files, ["ab12cd34-foto.jpg"])
        // ohne Text und ohne Anhang ist es keine Nachricht
        XCTAssertTrue(OutboxLogic.decode(OutboxLogic.encode([OutItem(id: "h", key: "k", text: "", at: 1)])).isEmpty)
    }
}
