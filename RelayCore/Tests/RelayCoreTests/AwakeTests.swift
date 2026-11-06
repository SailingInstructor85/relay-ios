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
}
