import XCTest
@testable import RelayCore

final class SearchTests: XCTestCase {
    private func session(_ key: String, title: String = "t", state: String = "idle", bg: Bool = false, last: Double = 1, asks: Bool = false) -> Session {
        Session.from(["key": .string(key), "title": .string(title), "state": .string(state), "background": .bool(bg),
                      "last_activity": .number(last), "cwd": "/home/m/proj", "tmux_session": .string("tm-\(key.suffix(1))")])!
    }

    func testHitsOnePerSessionNewestFirst() {
        let r = JSON.parse(#"{"hits":[{"session_key":"claude:c1:a","snippet":"x","ts":5},{"session_key":"claude:c1:b","snippet":"y","ts":9},{"session_key":"claude:c1:a","snippet":"z","ts":7}]}"#)!
        let h = ContentSearch.hits(r)
        XCTAssertEqual(h.map(\.sessionKey), ["claude:c1:b", "claude:c1:a"])
        XCTAssertEqual(h[1].snippet, "x")
    }

    func testConversationsOnlyListedSessions() {
        let s = [session("claude:c1:a", title: "Alpha"), session("claude:c1:b", bg: true)]
        let hits = ["claude:c1:a", "claude:c1:b", "claude:c1:zz"].map {
            ContentSearch.Hit(sessionKey: $0, tool: "claude", alias: "c1", role: "user", snippet: "s", ts: 1)
        }
        let c = ContentSearch.conversations(hits, sessions: s)
        XCTAssertEqual(c.map(\.session.name), ["Alpha"])
    }

    func testWanted() {
        XCTAssertFalse(ContentSearch.wanted(" a "))
        XCTAssertTrue(ContentSearch.wanted("ab"))
    }

    func testMatchesAllWords() {
        XCTAssertTrue(AppSearch.matches("Das Gespräch über Äpfel", "apfel gesprach"))
        XCTAssertFalse(AppSearch.matches("nur eins", "eins zwei"))
        XCTAssertFalse(AppSearch.matches("x", "  "))
    }

    func testJarvisSearch() {
        let t = [JarvisTurn(q: "wetter heute", a: "sonnig", voice: false, ts: 1), JarvisTurn(q: "mail", a: "keine neue", voice: true, ts: 2)]
        XCTAssertEqual(AppSearch.jarvis(t, query: "neue mail").map(\.q), ["mail"])
        XCTAssertEqual(AppSearch.jarvis(t, query: "e").count, 2)
    }

    func testSnippet() {
        let s = AppSearch.snippet(String(repeating: "a ", count: 100) + "ZIEL " + String(repeating: "b ", count: 100), query: "ziel")
        XCTAssertTrue(s.contains("ZIEL"))
        XCTAssertTrue(s.hasPrefix("…") && s.hasSuffix("…"))
    }

    func testShareBody() {
        XCTAssertEqual(ShareLogic.body(message: " Schau mal ", paths: ["/a/x.png", "/a/y.pdf"], text: nil), "Schau mal\n\n/a/x.png\n/a/y.pdf")
        XCTAssertEqual(ShareLogic.body(message: "", paths: [], text: " nur Text "), "nur Text")
        XCTAssertEqual(ShareLogic.body(message: "Hi", paths: [], text: nil), "Hi")
        XCTAssertFalse(ShareLogic.canSend(files: 0, text: " ", message: ""))
        XCTAssertTrue(ShareLogic.canSend(files: 1, text: nil, message: ""))
    }

    func testCleanNameAndSize() {
        XCTAssertEqual(ShareLogic.cleanName("a/b/foto.jpg", ext: nil, n: 1), "foto.jpg")
        XCTAssertEqual(ShareLogic.cleanName(nil, ext: "png", n: 2), "shared-2.png")
        XCTAssertEqual(ShareLogic.sizeLabel(2_621_440), "2.5 MB")
        XCTAssertEqual(ShareLogic.sizeLabel(2048), "2 KB")
    }

    func testTargets() {
        let s = [session("claude:c1:a", title: "alt", last: 1), session("claude:c1:b", title: "neu", last: 9),
                 session("claude:c1:c", title: "wartet", state: "needs_input", last: 5), session("claude:c1:d", state: "exited"),
                 session("claude:c1:e", bg: true)]
        XCTAssertEqual(ShareLogic.targets(s, lastKey: "", query: "").map(\.name), ["wartet", "neu", "alt"])
        XCTAssertEqual(ShareLogic.targets(s, lastKey: "claude:c1:a", query: "").map(\.name), ["alt", "wartet", "neu"])
        XCTAssertEqual(ShareLogic.targets(s, lastKey: "", query: "neu").map(\.name), ["neu"])
    }

    func testConnText() {
        XCTAssertTrue(ConnText.isPrivateLAN("192.168.1.20"))
        XCTAssertTrue(ConnText.isPrivateLAN("172.20.0.1"))
        XCTAssertFalse(ConnText.isPrivateLAN("172.40.0.1"))
        XCTAssertFalse(ConnText.isPrivateLAN("mein.host.de"))
        XCTAssertTrue(ConnText.noRoute(host: "10.0.0.1", vpn: false))
        XCTAssertFalse(ConnText.noRoute(host: "10.0.0.1", vpn: true))
    }

    func testFavDirs() {
        XCTAssertEqual(FavDirs.toggled(["/a"], "/b"), ["/a", "/b"])
        XCTAssertEqual(FavDirs.toggled(["/a", "/b"], "/a"), ["/b"])
        XCTAssertEqual(FavDirs.ordered(favs: ["/b"], recent: ["/a", "/b"]), ["/b", "/a"])
    }

    func testStand() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(StandText.text(lastActivity: 10_000 - 300, now: now), "Stand: vor 5 Min.")
        XCTAssertEqual(StandText.text(lastActivity: 0, now: now), "")
    }

    func testProfile() {
        let p = ProfileFields.make(fields: ["full_name": " Max M ", "city": ""], emails: ["a@b.de", " "])
        XCTAssertEqual(p["full_name"].string, "Max M")
        XCTAssertTrue(p["city"].isNull)
        XCTAssertEqual(p["emails"].array.count, 1)
        XCTAssertEqual(ProfileFields.splitEmails("a@b.de, c@d.de"), ["a@b.de", "c@d.de"])
        XCTAssertTrue(ProfileFields.looksSensitive("4111 1111 1111 1111"))
        XCTAssertTrue(ProfileFields.looksSensitive("DE89 3704 0044 0532 0130 00"))
        XCTAssertFalse(ProfileFields.looksSensitive("Hauptstr. 5"))
    }

    func testVaultDrop() {
        XCTAssertEqual(VaultDrop.name(paths: ["/u/2026/daniel.pdf"]), "Ablage: daniel.pdf")
        XCTAssertEqual(VaultDrop.name(paths: ["/a", "/b", "/c"]), "Ablage: 3 Dateien")
        let p = VaultDrop.prompt(paths: ["/u/daniel.pdf"], note: " Bibel, aufheben ")
        XCTAssertTrue(p.contains("- /u/daniel.pdf"))
        XCTAssertTrue(p.contains("Hinweis von Martin: Bibel, aufheben"))
        XCTAssertTrue(p.contains("\"01 Inbox/\""))
        XCTAssertTrue(p.contains("\"07 Anhänge/\""))
        XCTAssertFalse(VaultDrop.prompt(paths: ["/x"], note: "  ").contains("Hinweis"))
    }
}
