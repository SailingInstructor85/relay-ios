import XCTest
@testable import RelayCore

final class AwakeTests: XCTestCase {
    func testAwakeWhileWatchedAndTouched() {
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(AwakePolicy.keepAwake(watching: true, lastTouch: t0, now: t0))
        XCTAssertTrue(AwakePolicy.keepAwake(watching: true, lastTouch: t0, now: t0.addingTimeInterval(59)))
        XCTAssertFalse(AwakePolicy.keepAwake(watching: true, lastTouch: t0, now: t0.addingTimeInterval(60)))
        XCTAssertFalse(AwakePolicy.keepAwake(watching: false, lastTouch: t0, now: t0))
    }

    func testNextCheck() {
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(AwakePolicy.nextCheck(watching: true, lastTouch: t0, now: t0.addingTimeInterval(20)) ?? 0, 40, accuracy: 0.001)
        XCTAssertNil(AwakePolicy.nextCheck(watching: true, lastTouch: t0, now: t0.addingTimeInterval(61)))
        XCTAssertNil(AwakePolicy.nextCheck(watching: false, lastTouch: t0, now: t0))
    }

    func testRecordingKeepsAwakeForTenMinutes() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let old = t0.addingTimeInterval(-3600)  // last touch long ago, no chat open
        func on(_ since: Date?, _ dt: TimeInterval, watching: Bool = false) -> Bool {
            AwakePolicy.keepAwake(watching: watching, lastTouch: old, recordingSince: since, pinned: false, now: t0.addingTimeInterval(dt))
        }
        XCTAssertTrue(on(t0, 0))
        XCTAssertTrue(on(t0, 599))
        XCTAssertFalse(on(t0, 600))
        XCTAssertFalse(on(t0, 1200))
        XCTAssertFalse(on(nil, 0))  // recording ended early: normal lock at once
        XCTAssertFalse(on(t0, 600, watching: true))  // chat open but untouched for long: no extra time
    }

    func testRecordingAndTouchAddUp() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let now = t0.addingTimeInterval(700)
        // recording past its limit, but the chat was touched 10 s ago: the touch rule still holds
        XCTAssertTrue(AwakePolicy.keepAwake(watching: true, lastTouch: now.addingTimeInterval(-10), recordingSince: t0, pinned: false, now: now))
        XCTAssertEqual(AwakePolicy.nextCheck(watching: true, lastTouch: now.addingTimeInterval(-10), recordingSince: t0, pinned: false, now: now) ?? 0, 50, accuracy: 0.001)
        // both running: the next check is when the first one runs out
        let mid = t0.addingTimeInterval(580)
        XCTAssertEqual(AwakePolicy.nextCheck(watching: true, lastTouch: mid, recordingSince: t0, pinned: false, now: mid) ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(AwakePolicy.nextCheck(watching: false, lastTouch: mid, recordingSince: t0, pinned: false, now: t0.addingTimeInterval(100)) ?? 0, 500, accuracy: 0.001)
        XCTAssertNil(AwakePolicy.nextCheck(watching: false, lastTouch: t0, recordingSince: t0, pinned: false, now: t0.addingTimeInterval(601)))
    }

    func testPinnedStaysOnWithoutTimer() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let late = t0.addingTimeInterval(5000)
        XCTAssertTrue(AwakePolicy.keepAwake(watching: false, lastTouch: t0, recordingSince: t0, pinned: true, now: late))
        XCTAssertNil(AwakePolicy.nextCheck(watching: false, lastTouch: t0, recordingSince: nil, pinned: true, now: late))
    }
}
