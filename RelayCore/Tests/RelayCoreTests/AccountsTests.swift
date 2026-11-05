import XCTest
@testable import RelayCore

final class AccountsTests: XCTestCase {
    func testHelperMissing() {
        XCTAssertTrue(AccountsText.isHelperMissing("usage helper unavailable: no such file"))
        XCTAssertFalse(AccountsText.isHelperMissing("token expired"))
        XCTAssertTrue(AccountsText.errorText("usage helper unavailable").contains("claude-pool"))
        XCTAssertEqual(AccountsText.errorText("token expired"), "token expired")
    }

    func testUsageParseForecastExtras() {
        let o = JSON.object(["alias": "c1", "tool": "claude", "plan": "max", "windows": [
            ["name": "5 h", "pct": 40.0, "resets_at": 100.0, "forecast": ["unused_at_reset_pct": 30.4, "rate_pct_h": 5.0, "basis": "recent"]],
            ["name": "week", "pct": 80.0, "resets_at": 200.0, "forecast": ["runs_out_at": 150.0, "unused_at_reset_pct": 0.0]],
        ], "extras": ["as_of": 5.0, "cloud_credit": ["limit": 10.0, "used": 4.0, "left": 6.0, "currency": "USD", "expires_at": 9.0, "locked": false],
                      "extra_usage": ["enabled": true, "currency": "USD", "used": 1.5, "limit": 20.0], "by_product": [["name": "Code", "pct": 12.0]]]])
        let a = UsageAccount.from(o)
        XCTAssertEqual(AccountsText.forecast(a.windows[0], clock: { _ in "x" }), "Reicht bis zum Reset, ca. 30 % bleiben ungenutzt")
        XCTAssertEqual(AccountsText.forecast(a.windows[1], clock: { _ in "14:05" }), "leer um 14:05")
        XCTAssertEqual(AccountsText.forecast(UsageWindow(name: "5 h", pct: 1, resetsAt: 0), clock: { _ in "" }), "")
        XCTAssertEqual(a.extras?.credit?.left, 6)
        XCTAssertEqual(a.extras?.extra?.limit, 20)
        XCTAssertNil(a.extras?.extra?.balance)
        XCTAssertEqual(a.extras?.byProduct.first?.name, "Code")
        XCTAssertNil(UsageAccount.from(["alias": "x"]).extras)
        XCTAssertEqual(AccountsText.money(6, "USD"), "6,00 $")
    }

    func testClosedAndMemory() {
        XCTAssertEqual(AccountsText.closedReason("pressure", idleH: 3), "idle 3 h, RAM knapp")
        XCTAssertEqual(AccountsText.closedReason("idle", idleH: 23), "idle 23 h")
        XCTAssertEqual(AccountsText.closedReason("user", idleH: nil), "von dir geschlossen")
        XCTAssertEqual(AccountsText.memory(mb: 251, swapMb: 100), "251 MB + 100 MB Swap")
        XCTAssertEqual(AccountsText.relative(50, max: 200), 0.25)
        XCTAssertEqual(AccountsText.uptime(3 * 3600 + 120), "3 Std. 2 Min.")
    }

    func testTokensAndCloud() {
        XCTAssertEqual(AccountsText.tokens(950), "950")
        XCTAssertEqual(AccountsText.tokens(12_340), "12,3k")
        XCTAssertEqual(AccountsText.tokens(2_500_000), "2,5M")
        XCTAssertEqual(AccountsText.cloudState("waiting"), "Wartet auf dich")
        let c = CloudSession.from(["id": "x", "cost_usd": 1.25, "model": "opus"])
        XCTAssertEqual(c?.costUsd, 1.25); XCTAssertEqual(c?.model, "opus")
    }

    func testPowerAndConfig() {
        let p = PowerStatus.from(["sessions": 3.0, "tasks": 1.0, "uptime_s": 60.0, "reopen": true, "busy": [["key": "k", "title": "T", "alias": "c1"]]])
        XCTAssertEqual(p.busy.count, 1); XCTAssertTrue(p.reopen); XCTAssertEqual(p.sessions, 3)
        let c = OverviewConfig.from(["overview": ["alias": "c1", "model": "haiku", "effort": "low"], "poll_fallback_s": 15.0])
        var n = c; n.model = "opus"
        XCTAssertEqual(n.diff(from: c), ["overview_model": .string("opus")])
        XCTAssertTrue(c.diff(from: c).isEmpty)
    }
}
