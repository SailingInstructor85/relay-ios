import XCTest
@testable import RelayCore

final class HostsTests: XCTestCase {
    func testCandidatesTrimAndDedupe() {
        XCTAssertEqual(HostChoice.candidates([" 192.168.58.40 ", "", "100.73.162.18", "192.168.58.40"]), ["192.168.58.40", "100.73.162.18"])
        XCTAssertEqual(HostChoice.candidates(["", "  "]), [])
    }

    func testOrderPrefersLastGood() {
        let c = ["192.168.58.40", "100.73.162.18"]
        XCTAssertEqual(HostChoice.order(candidates: c, lastGood: "100.73.162.18"), ["100.73.162.18", "192.168.58.40"])
        XCTAssertEqual(HostChoice.order(candidates: c, lastGood: ""), c)
        XCTAssertEqual(HostChoice.order(candidates: c, lastGood: "10.0.0.1"), c)
    }

    func testPick() {
        let c = ["192.168.58.40", "100.73.162.18"]
        XCTAssertEqual(HostChoice.pick(candidates: c, reachable: ["100.73.162.18"], lastGood: ""), "100.73.162.18")
        XCTAssertEqual(HostChoice.pick(candidates: c, reachable: ["9.9.9.9"], lastGood: "100.73.162.18"), "100.73.162.18")
        XCTAssertEqual(HostChoice.pick(candidates: c, reachable: [], lastGood: ""), "192.168.58.40")
        XCTAssertNil(HostChoice.pick(candidates: [], reachable: [], lastGood: ""))
    }

    func testLabel() {
        XCTAssertEqual(HostChoice.label(active: "100.73.162.18", candidates: ["a", "100.73.162.18"]), "über 100.73.162.18")
        XCTAssertEqual(HostChoice.label(active: "a", candidates: ["a"]), "")
        XCTAssertEqual(HostChoice.label(active: "", candidates: ["a", "b"]), "")
    }

    func testNoRouteNeedsAllHostsPrivate() {
        XCTAssertTrue(ConnText.noRoute(hosts: ["192.168.58.40"], vpn: false))
        XCTAssertFalse(ConnText.noRoute(hosts: ["192.168.58.40", "100.73.162.18"], vpn: false))
        XCTAssertFalse(ConnText.noRoute(hosts: ["192.168.58.40"], vpn: true))
        XCTAssertFalse(ConnText.noRoute(hosts: [], vpn: false))
    }
}
