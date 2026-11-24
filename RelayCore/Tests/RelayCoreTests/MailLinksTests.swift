import XCTest
@testable import RelayCore

final class MailLinksTests: XCTestCase {
    func testFindsWebAndMailLinksInOrder() {
        let text = "Hallo,\n\nder Plan steht unter https://example.org/plan?x=1. Fragen an anna.muster@example.org oder www.example.org/hilfe."
        let links = MailLinks.find(text)
        XCTAssertEqual(links.map(\.target), ["https://example.org/plan?x=1", "mailto:anna.muster@example.org", "https://www.example.org/hilfe"])
        XCTAssertEqual(links.map(\.shown), ["https://example.org/plan?x=1", "anna.muster@example.org", "www.example.org/hilfe"])
        XCTAssertEqual(links.map(\.host), ["example.org", "anna.muster@example.org", "www.example.org"])
        XCTAssertTrue(links.allSatisfy { $0.warning == nil })
        XCTAssertTrue(links[1].isMail)
        // die Stelle passt zum Text (UTF-16)
        let ns = text as NSString
        for l in links { XCTAssertEqual(ns.substring(with: NSRange(location: l.start, length: l.end - l.start)), l.shown) }
    }

    func testPositionsAfterUmlautsAndEmoji() {
        let text = "Grüße 👋 und schöne Übersicht: https://example.org/ü"
        let l = MailLinks.find(text)
        XCTAssertEqual(l.count, 1)
        XCTAssertEqual((text as NSString).substring(with: NSRange(location: l[0].start, length: l[0].end - l[0].start)), l[0].shown)
    }

    func testOnlyHttpHttpsMailto() {
        XCTAssertTrue(MailLinks.allowed("https://example.org"))
        XCTAssertTrue(MailLinks.allowed("HTTP://example.org"))
        XCTAssertTrue(MailLinks.allowed("mailto:a@example.org"))
        XCTAssertFalse(MailLinks.allowed("javascript:alert(1)"))
        XCTAssertFalse(MailLinks.allowed("file:///etc/passwd"))
        XCTAssertFalse(MailLinks.allowed("tel:110"))
        XCTAssertFalse(MailLinks.allowed("relay://x"))
        XCTAssertEqual(MailLinks.find("Bitte javascript:alert(1) oder file:///etc/passwd oder tel:110 öffnen."), [])
    }

    func testMailtoPrefixBelongsToTheLink() {
        let l = MailLinks.find("Schreib an mailto:buero@handwerk.example.org bitte.")
        XCTAssertEqual(l.count, 1)
        XCTAssertEqual(l[0].shown, "mailto:buero@handwerk.example.org")
        XCTAssertEqual(l[0].target, "mailto:buero@handwerk.example.org")
    }

    func testWarnsWhenAddressStartsWithAnotherName() {
        let l = MailLinks.find("Jetzt anmelden: https://www.bank.example@boese.example/login")
        XCTAssertEqual(l.count, 1)
        XCTAssertEqual(l[0].host, "boese.example")
        XCTAssertEqual(l[0].warning, "Die Adresse beginnt mit „www.bank.example“, führt aber zu boese.example.")
    }

    func testWarnsWhenTextNamesAnotherAddress() {
        let a = MailLinks.find("Zum Konto: www.bank.example <https://boese.example/konto>")
        // das Ziel steht eingeklammert hinter dem genannten Namen
        let target = a.first { $0.host == "boese.example" }
        XCTAssertEqual(target?.warning, "Im Text steht www.bank.example, der Link führt aber zu boese.example.")
        let md = MailLinks.find("Hier klicken: [bank.example](https://boese.example/x)")
        XCTAssertEqual(md.first { $0.host == "boese.example" }?.warning, "Im Text steht bank.example, der Link führt aber zu boese.example.")
    }

    func testNoWarningWhenTextAndTargetBelongTogether() {
        XCTAssertNil(MailLinks.find("Seite: bank.example <https://www.bank.example/konto>").last?.warning)
        XCTAssertNil(MailLinks.find("Seite: bank.example (https://konto.bank.example/)").last?.warning)
        XCTAssertNil(MailLinks.find("Anna Muster <https://example.org/a>").last?.warning)
        XCTAssertNil(MailLinks.find("Siehe (https://example.org/a) und https://example.org/b").first?.warning)
    }

    func testWarnsOnNumbersAndLookalikeNames() {
        XCTAssertEqual(MailLinks.find("http://192.168.1.20/login").first?.warning, "Das Ziel ist eine Zahlenadresse (192.168.1.20), kein Name.")
        XCTAssertNotNil(MailLinks.find("https://xn--bnk-sna.example/login").first?.warning)
        XCTAssertNil(MailLinks.find("https://example.org:8443/x").first?.warning)
        XCTAssertEqual(MailLinks.find("https://example.org:8443/x").first?.host, "example.org")
    }

    func testRelatedHosts() {
        XCTAssertTrue(MailLinks.related("www.example.org", "example.org"))
        XCTAssertTrue(MailLinks.related("a.b.example.org", "example.org"))
        XCTAssertFalse(MailLinks.related("example.org.boese.example", "example.org"))
        XCTAssertFalse(MailLinks.related("notexample.org", "example.org"))
    }
}
