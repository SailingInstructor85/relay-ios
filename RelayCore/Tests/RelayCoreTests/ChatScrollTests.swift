import XCTest
@testable import RelayCore

final class ChatScrollTests: XCTestCase {
    func testStartsFollowingWithoutButton() {
        let s = ChatScroll()
        XCTAssertTrue(s.follows)
        XCTAssertFalse(s.showsJump)
    }

    func testDistance() {
        XCTAssertEqual(ChatScroll.distance(offset: 0, content: 2000, viewport: 500), 1500)
        XCTAssertEqual(ChatScroll.distance(offset: 1500, content: 2000, viewport: 500), 0)
        // kurzer Inhalt und Nachfedern über das Ende hinaus: nie negativ
        XCTAssertEqual(ChatScroll.distance(offset: 0, content: 200, viewport: 500), 0)
        XCTAssertEqual(ChatScroll.distance(offset: 1540, content: 2000, viewport: 500), 0)
    }

    /// Der gespeicherte Verlauf wird geladen: Der Inhalt ist plötzlich lang, die Position steht noch oben. Das ist
    /// kein Hochscrollen, die Ansicht soll ans Ende gehen.
    func testLoadingHistoryKeepsFollowing() {
        var s = ChatScroll()
        s.moved(offset: 0, content: 100, viewport: 500)
        s.moved(offset: 0, content: 3000, viewport: 500)
        XCTAssertTrue(s.follows)
        s.moved(offset: 2500, content: 3000, viewport: 500)
        XCTAssertTrue(s.follows)
    }

    /// Eine Antwort läuft ein: Der Inhalt wächst, die Position bleibt, dann scrollt die Ansicht nach.
    func testGrowingContentKeepsFollowing() {
        var s = ChatScroll()
        s.moved(offset: 1500, content: 2000, viewport: 500)
        s.moved(offset: 1500, content: 2300, viewport: 500)
        XCTAssertTrue(s.follows)
        s.moved(offset: 1800, content: 2300, viewport: 500)
        XCTAssertTrue(s.follows)
        XCTAssertFalse(s.showsJump)
    }

    func testScrollingUpShowsButtonAndStopsFollowing() {
        var s = ChatScroll()
        s.moved(offset: 1500, content: 2000, viewport: 500)
        s.moved(offset: 1300, content: 2000, viewport: 500)
        XCTAssertFalse(s.follows)
        XCTAssertTrue(s.showsJump)
        // neuer Inhalt holt den Verlauf nicht zurück
        s.moved(offset: 1300, content: 2600, viewport: 500)
        XCTAssertTrue(s.showsJump)
        // ein Stück nach unten, aber nicht bis ans Ende: der Knopf bleibt
        s.moved(offset: 1700, content: 2600, viewport: 500)
        XCTAssertTrue(s.showsJump)
    }

    func testSmallMoveNearEndStillFollows() {
        var s = ChatScroll()
        s.moved(offset: 1500, content: 2000, viewport: 500)
        s.moved(offset: 1500 - ChatScroll.tolerance + 2, content: 2000, viewport: 500)
        XCTAssertTrue(s.follows)
    }

    func testBackAtEndFollowsAgain() {
        var s = ChatScroll()
        s.moved(offset: 1500, content: 2000, viewport: 500)
        s.moved(offset: 900, content: 2000, viewport: 500)
        XCTAssertTrue(s.showsJump)
        s.moved(offset: 1490, content: 2000, viewport: 500)
        XCTAssertTrue(s.follows)
        XCTAssertFalse(s.showsJump)
    }

    /// Der Knopf: sofort wieder folgen, auch während die Ansicht noch nach unten läuft.
    func testJump() {
        var s = ChatScroll()
        s.moved(offset: 1500, content: 2000, viewport: 500)
        s.moved(offset: 200, content: 2000, viewport: 500)
        XCTAssertTrue(s.showsJump)
        s.jump()
        XCTAssertFalse(s.showsJump)
        s.moved(offset: 600, content: 2000, viewport: 500)
        s.moved(offset: 1100, content: 2000, viewport: 500)
        XCTAssertTrue(s.follows)
        s.moved(offset: 1500, content: 2000, viewport: 500)
        XCTAssertTrue(s.follows)
    }

    /// Die Tastatur geht auf: Der Ausschnitt wird kleiner, die Position bleibt. Kein Hochscrollen.
    func testKeyboardOpeningKeepsFollowing() {
        var s = ChatScroll()
        s.moved(offset: 1500, content: 2000, viewport: 500)
        s.moved(offset: 1500, content: 2000, viewport: 200)
        XCTAssertTrue(s.follows)
        // und wieder zu: Die Position rutscht mit dem größeren Ausschnitt zurück, das Ende steht im Bild
        s.moved(offset: 1800, content: 2000, viewport: 200)
        s.moved(offset: 1500, content: 2000, viewport: 500)
        XCTAssertTrue(s.follows)
    }

    /// Die Zeile „Ich höre…“ verschwindet, der Inhalt wird kürzer und die Position rutscht nach: weiter unten.
    func testShrinkingContentAtEndKeepsFollowing() {
        var s = ChatScroll()
        s.moved(offset: 1500, content: 2000, viewport: 500)
        s.moved(offset: 1440, content: 1940, viewport: 500)
        XCTAssertTrue(s.follows)
    }

    func testNoViewportDoesNothing() {
        var s = ChatScroll()
        s.moved(offset: 500, content: 2000, viewport: 0)
        s.moved(offset: 0, content: 2000, viewport: 0)
        XCTAssertTrue(s.follows)
    }
}
