import XCTest
@testable import RelayCore

/// Tab-Rahmen: Beschriftungen, Sprünge von außen, Abzeichen.
final class TabsTests: XCTestCase {
    func testTabsInOrderWithGermanTitles() {
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Heute", "Dein Zug", "Sitzungen", "Posteingang", "Mehr"])
        XCTAssertEqual(Set(AppTab.allCases.map(\.symbol)).count, 5)
    }

    func testChatJumpLandsInSessions() {
        let t = TabRouting.target(.chat("claude:c1:abc"))
        XCTAssertEqual(t.tab, .sessions)
        XCTAssertEqual(t.path, [.chat("claude:c1:abc")])
    }

    func testVaultChatJump() {
        let t = TabRouting.target(.chat(VaultChat.key))
        XCTAssertEqual(t.tab, .sessions)
        XCTAssertEqual(t.path, [.vaultChat])
    }

    func testOpenQuestionLandsInYourTurn() {
        let t = TabRouting.target(.notice(ref: "s7", openQuestion: true))
        XCTAssertEqual(t.tab, .yourTurn)
        XCTAssertEqual(t.path, [.notice("s7")])
    }

    func testOtherNoticeLandsInMoreAboveTheList() {
        let t = TabRouting.target(.notice(ref: "s8", openQuestion: false))
        XCTAssertEqual(t.tab, .more)
        XCTAssertEqual(t.path, [.notices, .notice("s8")])
    }

    func testJarvisAndDrive() {
        XCTAssertEqual(TabRouting.target(.jarvis).tab, .today)
        XCTAssertEqual(TabRouting.target(.jarvis).path, [.jarvisListening])
        XCTAssertEqual(TabRouting.target(.drive).tab, .yourTurn)
        XCTAssertEqual(TabRouting.target(.drive).path, [.drive])
    }

    func testTabBarHiddenWhereTheViewHasItsOwnInput() {
        for r in [Route.chat("k"), .chatSearch("k", "q"), .jarvis, .jarvisListening, .jarvisAsk("x"), .drive, .vaultChat] {
            XCTAssertTrue(r.hidesTabBar, "\(r)")
        }
        for r in [Route.settings, .usage, .memory, .digest, .tokens, .notices, .notice("s1"), .routines, .mail("12"), .calendar] {
            XCTAssertFalse(r.hidesTabBar, "\(r)")
        }
    }

    func testBadge() {
        XCTAssertNil(TabRouting.badge(0))
        XCTAssertNil(TabRouting.badge(-1))
        XCTAssertEqual(TabRouting.badge(1), "1")
        XCTAssertEqual(TabRouting.badge(99), "99")
        XCTAssertEqual(TabRouting.badge(100), "99+")
    }
}
