import XCTest
@testable import RelayCore

final class SigningTests: XCTestCase {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Aufbau wie eine echte `embedded.mobileprovision`: binärer Umschlag, darin die Plist im Klartext.
    private func profile(_ plist: String) -> Data {
        var d = Data([0x30, 0x82, 0x1f, 0xa3, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02, 0xff, 0xfe, 0x00])
        d.append(Data(plist.utf8))
        d.append(Data([0xa0, 0x82, 0x0d, 0x3c, 0x30, 0x82, 0x04, 0x44, 0xff, 0x00, 0x80]))
        return d
    }

    private func plist(expiration: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>AppIDName</key>
        \t<string>Relay</string>
        \t<key>CreationDate</key>
        \t<date>2026-11-25T22:18:03Z</date>
        \t<key>ExpirationDate</key>
        \t\(expiration)
        \t<key>Name</key>
        \t<string>iOS Team Provisioning Profile: dev.relay.ios</string>
        \t<key>TimeToLive</key>
        \t<integer>7</integer>
        </dict>
        </plist>
        """
    }

    // MARK: Parser

    func testExpirationFromProfile() {
        let d = profile(plist(expiration: "<date>2026-12-02T22:18:03Z</date>"))
        XCTAssertEqual(Provisioning.expiration(in: d), date("2026-12-02T22:18:03Z"))
    }

    func testExpirationIsNotTheCreationDate() {
        let d = profile(plist(expiration: "<date>2026-12-02T22:18:03Z</date>"))
        XCTAssertNotEqual(Provisioning.expiration(in: d), date("2026-11-25T22:18:03Z"))
    }

    func testExpiredProfileStillParses() {
        let exp = Provisioning.expiration(in: profile(plist(expiration: "<date>2026-11-01T08:00:00Z</date>")))
        XCTAssertEqual(exp, date("2026-11-01T08:00:00Z"))
        XCTAssertTrue(SigningStatus(expiry: exp!, now: date("2026-11-26T20:00:00Z")).expired)
    }

    func testMissingFileOrKey() {
        XCTAssertNil(Provisioning.expiration(in: Data()))
        let ohne = plist(expiration: "<date>2026-12-02T22:18:03Z</date>").replacingOccurrences(of: "ExpirationDate", with: "Anderes")
        XCTAssertNil(Provisioning.expiration(in: profile(ohne)))
    }

    func testBrokenProfiles() {
        // nur Binärdaten
        XCTAssertNil(Provisioning.expiration(in: Data([0x30, 0x82, 0xff, 0x00, 0x01, 0xfe])))
        // Plist abgeschnitten, kein </plist>
        let cut = plist(expiration: "<date>2026-12-02T22:18:03Z</date>").replacingOccurrences(of: "</plist>", with: "")
        XCTAssertNil(Provisioning.expiration(in: profile(cut)))
        // Datum unlesbar
        XCTAssertNil(Provisioning.expiration(in: profile(plist(expiration: "<date>übermorgen</date>"))))
        // Wert ist kein Datum: das Datum dahinter gehört zu einem anderen Schlüssel
        let other = plist(expiration: "<string>nie</string>\n\t<key>Später</key>\n\t<date>2027-01-01T00:00:00Z</date>")
        XCTAssertNil(Provisioning.expiration(in: profile(other)))
    }

    // MARK: Texte

    func testLineSixDays() {
        // 02.12.2026 22:18 UTC ist in Berlin 23:18 am Mittwoch
        let st = SigningStatus(expiry: date("2026-12-02T22:18:00Z"), now: date("2026-11-26T19:30:00Z"))
        XCTAssertEqual(st.line(timeZone: berlin), "Signatur gültig bis Mi, 02.12., noch 6 Tage")
        XCTAssertFalse(st.warn)
        XCTAssertFalse(st.expired)
    }

    func testDayFollowsTheTimeZone() {
        // 23:30 UTC am Mittwoch ist in Berlin schon Donnerstag
        let st = SigningStatus(expiry: date("2026-12-02T23:30:00Z"), now: date("2026-11-26T19:30:00Z"))
        XCTAssertEqual(st.dayText(timeZone: berlin), "Do, 03.12.")
        XCTAssertEqual(st.timeText(timeZone: berlin), "00:30 Uhr")
        XCTAssertEqual(st.dayText(timeZone: TimeZone(identifier: "UTC")!), "Mi, 02.12.")
    }

    func testWarnFromThreeDays() {
        let exp = date("2026-12-02T22:18:00Z")
        XCTAssertFalse(SigningStatus(expiry: exp, now: exp.addingTimeInterval(-3 * 86400 - 60)).warn)
        XCTAssertTrue(SigningStatus(expiry: exp, now: exp.addingTimeInterval(-3 * 86400)).warn)
        XCTAssertTrue(SigningStatus(expiry: exp, now: exp.addingTimeInterval(-3600)).warn)
        XCTAssertTrue(SigningStatus(expiry: exp, now: exp.addingTimeInterval(60)).warn)
    }

    func testRemainingText() {
        let exp = date("2026-12-02T22:18:00Z")
        func t(_ secs: Double) -> String { SigningStatus(expiry: exp, now: exp.addingTimeInterval(-secs)).remainingText }
        XCTAssertEqual(t(6 * 86400 + 5000), "6 Tage")
        XCTAssertEqual(t(2 * 86400), "2 Tage")
        XCTAssertEqual(t(2 * 86400 - 1), "1 Tag")
        XCTAssertEqual(t(86400), "1 Tag")
        XCTAssertEqual(t(86400 - 1), "23 Stunden")
        XCTAssertEqual(t(2 * 3600), "2 Stunden")
        XCTAssertEqual(t(3600 + 10), "1 Stunde")
        XCTAssertEqual(t(600), "weniger als 1 Stunde")
    }

    func testBannerAndExpiredTexts() {
        let exp = date("2026-12-02T22:18:00Z")
        let soon = SigningStatus(expiry: exp, now: exp.addingTimeInterval(-2 * 86400 - 100))
        XCTAssertEqual(soon.bannerTitle(timeZone: berlin), "Die Signatur von Relay läuft in 2 Tagen ab (Mi, 02.12., 23:18 Uhr).")
        XCTAssertEqual(SigningStatus(expiry: exp, now: exp.addingTimeInterval(-86400 - 5)).bannerTitle(timeZone: berlin),
                       "Die Signatur von Relay läuft in 1 Tag ab (Mi, 02.12., 23:18 Uhr).")
        XCTAssertEqual(SigningStatus(expiry: exp, now: exp.addingTimeInterval(-5 * 3600 - 5)).bannerTitle(timeZone: berlin),
                       "Die Signatur von Relay läuft in 5 Stunden ab (Mi, 02.12., 23:18 Uhr).")
        let over = SigningStatus(expiry: exp, now: exp.addingTimeInterval(3600))
        XCTAssertTrue(over.expired)
        XCTAssertEqual(over.line(timeZone: berlin), "Signatur abgelaufen seit Mi, 02.12., 23:18 Uhr")
        XCTAssertEqual(over.bannerTitle(timeZone: berlin), "Die Signatur von Relay ist abgelaufen (Mi, 02.12., 23:18 Uhr).")
        XCTAssertTrue(SigningStatus.wifiHint.contains("WLAN"))
    }

    func testUsageDetail() {
        let st = SigningStatus(expiry: date("2026-12-02T22:18:00Z"), now: date("2026-11-26T19:30:00Z"))
        XCTAssertEqual(st.usageDetail, "signatur_bis=2026-12-02T22:18:00Z")
    }

    // MARK: Mitteilungen

    func testRemindersAllThreeWhenFarAway() {
        let exp = date("2026-12-02T22:18:00Z")
        let plan = SigningReminders.plan(expiry: exp, now: exp.addingTimeInterval(-6 * 86400), timeZone: berlin)
        XCTAssertEqual(plan.map(\.id), ["sign-72", "sign-48", "sign-24"])
        XCTAssertEqual(plan.map(\.fire), [72, 48, 24].map { exp.addingTimeInterval(-Double($0) * 3600) })
        XCTAssertTrue(plan[0].body.contains("in 3 Tagen ab"))
        XCTAssertTrue(plan[1].body.contains("in 2 Tagen ab"))
        XCTAssertTrue(plan[2].body.contains("in 1 Tag ab"))
        XCTAssertTrue(plan.allSatisfy { $0.body.contains("WLAN") })
    }

    func testRemindersOnlyFutureOnes() {
        let exp = date("2026-12-02T22:18:00Z")
        XCTAssertEqual(SigningReminders.plan(expiry: exp, now: exp.addingTimeInterval(-50 * 3600)).map(\.id), ["sign-48", "sign-24"])
        XCTAssertEqual(SigningReminders.plan(expiry: exp, now: exp.addingTimeInterval(-10 * 3600)).map(\.id), [])
        XCTAssertEqual(SigningReminders.plan(expiry: exp, now: exp.addingTimeInterval(100)).map(\.id), [])
        XCTAssertEqual(SigningReminders.ids, ["sign-72", "sign-48", "sign-24"])
    }

    // MARK: Update

    func testVersionCompare() {
        XCTAssertTrue(AppUpdate.isNewer("0.4.10", than: "0.4.9"))
        XCTAssertFalse(AppUpdate.isNewer("0.4.9", than: "0.4.10"))
        XCTAssertFalse(AppUpdate.isNewer("0.4.9", than: "0.4.9"))
        XCTAssertTrue(AppUpdate.isNewer("0.5", than: "0.4.13"))
        XCTAssertFalse(AppUpdate.isNewer("0.4", than: "0.4.0"))
        XCTAssertTrue(AppUpdate.isNewer("v1.0.0", than: "0.9.9"))
        XCTAssertTrue(AppUpdate.isNewer("0.4.14-beta", than: "0.4.13"))
        XCTAssertFalse(AppUpdate.isNewer("", than: "0.4.13"))
        XCTAssertFalse(AppUpdate.isNewer("kaputt", than: "0.4.13"))
    }

    func testLatestVersionFromSource() {
        let src = JSON.parse(#"{"name":"Relay iOS","apps":[{"name":"Relay","versions":[{"version":"0.4.14","buildVersion":"3"}]}]}"#)!
        XCTAssertEqual(AppUpdate.latestVersion(in: src), "0.4.14")
        XCTAssertEqual(AppUpdate.available(latest: AppUpdate.latestVersion(in: src), own: "0.4.13"), "0.4.14")
        XCTAssertNil(AppUpdate.available(latest: AppUpdate.latestVersion(in: src), own: "0.4.14"))
        XCTAssertNil(AppUpdate.available(latest: AppUpdate.latestVersion(in: src), own: "0.4.15"))
        XCTAssertNil(AppUpdate.available(latest: nil, own: "0.4.13"))
    }

    func testBrokenSourceGivesNoVersion() {
        XCTAssertNil(AppUpdate.latestVersion(in: JSON.parse(#"{"apps":[]}"#)!))
        XCTAssertNil(AppUpdate.latestVersion(in: JSON.parse(#"{"apps":[{"versions":[]}]}"#)!))
        XCTAssertNil(AppUpdate.latestVersion(in: JSON.parse(#"{"apps":[{"versions":[{"version":""}]}]}"#)!))
        XCTAssertNil(AppUpdate.latestVersion(in: JSON.parse(#"{"apps":[{"versions":[{"version":"Not Found"}]}]}"#)!))
        XCTAssertNil(AppUpdate.latestVersion(in: JSON.parse(#"[1,2]"#)!))
    }

    func testCheckInterval() {
        XCTAssertTrue(AppUpdate.due(last: nil, now: 1000))
        XCTAssertFalse(AppUpdate.due(last: 1000, now: 1000 + 3600))
        XCTAssertTrue(AppUpdate.due(last: 1000, now: 1000 + 6 * 3600))
        XCTAssertTrue(AppUpdate.due(last: 5000, now: 1000), "Uhr zurückgestellt: wieder prüfen")
        XCTAssertEqual(AppUpdate.title("0.4.14"), "Update 0.4.14 verfügbar")
    }
}
