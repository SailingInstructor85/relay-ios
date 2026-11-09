import XCTest
@testable import RelayCore

final class TailnetTests: XCTestCase {
    func testTailnetAddresses() {
        XCTAssertTrue(Tailnet.isTailnetIPv4("100.73.162.18"))
        XCTAssertTrue(Tailnet.isTailnetIPv4("100.64.0.1"))
        XCTAssertTrue(Tailnet.isTailnetIPv4("100.127.255.255"))
        XCTAssertFalse(Tailnet.isTailnetIPv4("100.128.0.1"))
        XCTAssertFalse(Tailnet.isTailnetIPv4("100.63.0.1"))
        XCTAssertFalse(Tailnet.isTailnetIPv4("192.168.58.40"))
        XCTAssertFalse(Tailnet.isTailnetIPv4("100.73.162"))
        XCTAssertTrue(Tailnet.isTailnetIPv6("fd7a:115c:a1e0::1"))
        XCTAssertFalse(Tailnet.isTailnetIPv6("fe80::1"))
    }

    func testTailnetHosts() {
        XCTAssertTrue(Tailnet.isTailnetHost("100.73.162.18"))
        XCTAssertTrue(Tailnet.isTailnetHost("arch.tail1234.ts.net"))
        XCTAssertTrue(Tailnet.isTailnetHost("arch"))
        XCTAssertFalse(Tailnet.isTailnetHost("192.168.58.40"))
        XCTAssertFalse(Tailnet.isTailnetHost("arch.local"))
        XCTAssertFalse(Tailnet.isTailnetHost("localhost"))
        XCTAssertFalse(Tailnet.isTailnetHost("127.0.0.1"))
        XCTAssertFalse(Tailnet.isTailnetHost(""))
        XCTAssertTrue(Tailnet.needsTailnet(hosts: ["192.168.58.40", "100.73.162.18"]))
        XCTAssertFalse(Tailnet.needsTailnet(hosts: ["192.168.58.40"]))
    }

    func testShowHint() {
        let hosts = ["192.168.58.40", "100.73.162.18"]
        XCTAssertTrue(Tailnet.showHint(failed: true, network: true, hosts: hosts, tailnetUp: false))
        // Tailscale an, nur das Gateway antwortet nicht: kein Hinweis
        XCTAssertFalse(Tailnet.showHint(failed: true, network: true, hosts: hosts, tailnetUp: true))
        XCTAssertFalse(Tailnet.showHint(failed: false, network: true, hosts: hosts, tailnetUp: false))
        XCTAssertFalse(Tailnet.showHint(failed: true, network: false, hosts: hosts, tailnetUp: false))
        XCTAssertFalse(Tailnet.showHint(failed: true, network: true, hosts: ["192.168.58.40"], tailnetUp: false))
    }

    func testInterfaces() {
        XCTAssertTrue(Tailnet.tailnetUp([("en0", "192.168.58.20"), ("utun4", "100.101.5.7")]))
        XCTAssertFalse(Tailnet.tailnetUp([("en0", "192.168.58.20"), ("utun0", "fe80::1")]))
        XCTAssertFalse(Tailnet.tailnetUp([("pdp_ip0", "100.70.1.2")]))  // Mobilfunk-CGNAT ist kein Tailscale
        XCTAssertFalse(Tailnet.tailnetUp([]))
    }

    func testShortcutURL() {
        XCTAssertEqual(Tailnet.shortcutURL(name: "Tailscale verbinden")?.absoluteString,
                       "shortcuts://x-callback-url/run-shortcut?name=Tailscale%20verbinden&x-success=relay%3A%2F%2Ftailscale-verbunden"
                       + "&x-cancel=relay%3A%2F%2Ftailscale-verbunden&x-error=relay%3A%2F%2Ftailscale-fehler")
        XCTAssertEqual(Tailnet.shortcutURL(name: "Tailscale & VPN")?.absoluteString.contains("name=Tailscale%20%26%20VPN&"), true)
        XCTAssertNil(Tailnet.shortcutURL(name: "  "))
    }

    func testCallback() {
        XCTAssertEqual(Tailnet.callback(URL(string: "relay://tailscale-verbunden")!), .connected)
        XCTAssertEqual(Tailnet.callback(URL(string: "relay://tailscale-fehler?errorMessage=Nicht%20gefunden")!), .failed("Nicht gefunden"))
        XCTAssertNil(Tailnet.callback(URL(string: "relay://etwas")!))
        XCTAssertNil(Tailnet.callback(URL(fileURLWithPath: "/tmp/a.pdf")))
        XCTAssertTrue(Tailnet.failureText(shortcut: "X", message: "").contains("„X“"))
        XCTAssertTrue(Tailnet.failureText(shortcut: "X", message: "weg").hasSuffix("(weg)"))
    }
}
