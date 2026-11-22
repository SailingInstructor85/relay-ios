import XCTest
@testable import RelayCore

final class InboxTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-11-22 12:00 UTC (ein Sonntag).
    private let noon = Date(timeIntervalSince1970: 1_795_348_800)

    // Antwort von inbox_feed, Felder wie in gateway/src/notifyd/inbox.py (feed).
    private let feedJSON = """
    {"items": [
      {"type": "mail", "id": "412", "source": "mail", "account": "WEB.DE", "title": "Anna Muster",
       "from": "Anna Muster <anna@example.org>", "subject": "Unterlagen zum Termin", "ts": 1795345200, "attachments": true},
      {"type": "chat", "id": "org.example.chat|Familie", "source": "signal", "app_label": "Signal", "title": "Familie",
       "sender": "Ben", "text": "Kommt ihr\\nam Sonntag?", "ts": 1795341600, "count": 3, "has_reply": true},
      {"type": "mail", "id": "398", "source": "mail", "account": "WEB.DE", "title": "rundbrief@example.org",
       "from": "rundbrief@example.org", "subject": "", "ts": 1795255200},
      {"type": "feed", "id": "x"},
      {"type": "mail", "subject": "ohne id"}
    ], "days": 7, "errors": {"messages": "bridge offline"}}
    """

    func testFeedDecoding() {
        let feed = InboxFeed.from(JSON.parse(feedJSON)!)
        XCTAssertEqual(feed.items.count, 3)
        XCTAssertEqual(feed.days, 7)
        XCTAssertEqual(feed.mailError, "")
        XCTAssertEqual(feed.messagesError, "bridge offline")
        let m = feed.items[0]
        XCTAssertEqual(m.kind, .mail)
        XCTAssertEqual(m.itemID, "412")
        XCTAssertEqual(m.id, "mail:412")
        XCTAssertEqual(m.account, "WEB.DE")
        XCTAssertEqual(m.who, "Anna Muster")
        XCTAssertEqual(m.headline, "Unterlagen zum Termin")
        XCTAssertEqual(m.preview, "")
        XCTAssertTrue(m.attachments)
        XCTAssertEqual(m.footer, "WEB.DE")
        XCTAssertEqual(m.avatarKey, "anna@example.org")
        let c = feed.items[1]
        XCTAssertEqual(c.kind, .chat)
        XCTAssertEqual(c.headline, "")
        XCTAssertEqual(c.preview, "Ben: Kommt ihr am Sonntag?")
        XCTAssertEqual(c.footer, "Signal · 3 Nachrichten")
        XCTAssertEqual(feed.items[2].headline, InboxText.noSubject)
        XCTAssertFalse(feed.items[2].attachments)
    }

    func testFeedWithoutErrorsOrItems() {
        let feed = InboxFeed.from(JSON.parse(#"{"items": [], "days": 7}"#)!)
        XCTAssertTrue(feed.items.isEmpty)
        XCTAssertEqual(feed.mailError, "")
        XCTAssertNil(InboxText.sourceFailure(feed))
        XCTAssertEqual(InboxFeed.from(.null).items, [])
    }

    func testSearchDecoding() {
        let r = InboxSearchResult.from(JSON.parse("""
        {"items": [{"type": "mail", "id": "77", "source": "mail", "account": "Archive", "title": "To Carla Beispiel",
                    "from": "ich@example.org", "subject": "Rechnung", "ts": 1700000000,
                    "snippet": "die  Rechnung\\nliegt bei", "sent": true, "attachments": true}],
         "q": "rechn", "mail_total": 120}
        """)!)
        XCTAssertEqual(r.query, "rechn")
        XCTAssertEqual(r.mailTotal, 120)
        XCTAssertEqual(r.items[0].preview, "die Rechnung liegt bei")
        XCTAssertTrue(r.items[0].sent)
        XCTAssertEqual(r.items[0].footer, "Archiv · Gesendet")
        XCTAssertEqual(InboxText.found(r), "1 Treffer für „rechn“ (von 120 Mails im Index)")
        let none = InboxSearchResult(items: [], query: "xyz")
        XCTAssertEqual(InboxText.found(none), "0 Treffer für „xyz“")
    }

    func testQuery() {
        XCTAssertNil(InboxText.query(" a "))
        XCTAssertEqual(InboxText.query("  ab "), "ab")
        XCTAssertNil(InboxText.query(String(repeating: "x", count: 201)))
        XCTAssertEqual(InboxText.query(String(repeating: "x", count: 200))?.count, 200)
    }

    func testMailDecoding() {
        // Felder wie inbox.mail plus reply_from aus daemon.rpc_inbox_mail
        let m = MailMessage.from(JSON.parse("""
        {"id": "412", "ts": 1795345200, "from": "Anna Muster <anna@example.org>", "to": "ich@example.org",
         "subject": "Unterlagen zum Termin", "account": "WEB.DE", "body": "Hallo,\\r\\n\\r\\nanbei die Unterlagen.\\nZweite Zeile.\\n\\n \\nGruß",
         "truncated": true, "attachments": ["plan.pdf", ""], "reply_from": ""}
        """)!)!
        XCTAssertEqual(m.id, "412")
        XCTAssertEqual(m.title, "Unterlagen zum Termin")
        XCTAssertEqual(m.attachments, ["plan.pdf"])
        XCTAssertTrue(m.truncated)
        XCTAssertEqual(m.paragraphs, ["Hallo,", "anbei die Unterlagen.\nZweite Zeile.", "Gruß"])
        XCTAssertNil(MailMessage.from(JSON.parse(#"{"subject": "x"}"#)!))
        XCTAssertEqual(MailMessage(id: "1").title, InboxText.noSubject)
        XCTAssertEqual(InboxText.paragraphs(""), [])
    }

    func testSuggestionDecoding() {
        // Felder wie mailsuggest.finish
        let groups = MailSuggestion.list(JSON.parse("""
        {"groups": [
          {"key": "rundbrief@example.org", "sender": "Beispiel Rundbrief", "address": "rundbrief@example.org", "reason": "newsletter",
           "count": 2, "total": 9, "first_ts": 1790000000, "last_ts": 1795000000, "examples": ["Ausgabe 12", "Ausgabe 11"],
           "accounts": ["WEB.DE"], "bytes": 1240000,
           "mails": [{"id": "301", "subject": "Ausgabe 12", "ts": 1795000000, "account": "WEB.DE", "size": 640000},
                     {"id": "250", "subject": "Ausgabe 11", "ts": 1790000000, "account": "WEB.DE", "size": 600000}]},
          {"key": "", "sender": "ohne Schlüssel"},
          {"key": "shop@example.com", "sender": "Beispielladen", "address": "shop@example.com", "reason": "old promotions",
           "count": 1, "total": 1, "examples": [], "accounts": [], "bytes": 0, "mails": []}
        ], "ts": 1795348800}
        """)!)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].sender, "Beispiel Rundbrief")
        XCTAssertEqual(groups[0].mails.map { $0.id }, ["301", "250"])
        XCTAssertEqual(groups[0].examples, ["Ausgabe 12", "Ausgabe 11"])
        XCTAssertEqual(groups[0].line, "2 Mails von 9 · Newsletter · 1,2 MB")
        XCTAssertEqual(groups[1].line, "1 Mail · Alte Werbung")
        XCTAssertEqual(InboxText.suggestionsSummary(groups), "2 Absender, 3 Mails")
        XCTAssertEqual(MailSuggestion.list(.null), [])
    }

    func testReasonAndSize() {
        XCTAssertEqual(InboxText.reason("notifications"), "Benachrichtigungen")
        XCTAssertEqual(InboxText.reason("promotions"), "Werbung")
        XCTAssertEqual(InboxText.reason("social"), "Soziale Netzwerke")
        XCTAssertEqual(InboxText.reason("bounces"), "Zustellberichte")
        XCTAssertEqual(InboxText.reason("etwas neues"), "etwas neues")
        XCTAssertEqual(InboxText.size(512), "512 B")
        XCTAssertEqual(InboxText.size(340_400), "340 kB")
        XCTAssertEqual(InboxText.size(2_000_000), "2,0 MB")
    }

    func testFailure() {
        let unknown = InboxText.failure(message: "unknown rpc 'inbox_feed'", remote: true)
        XCTAssertEqual(unknown.title, "Gateway liefert keinen Posteingang")
        XCTAssertTrue(unknown.missing)
        XCTAssertFalse(unknown.text.contains("unknown rpc"))
        let refused = InboxText.failure(message: "mail index locked", remote: true)
        XCTAssertEqual(refused.title, "Gateway liefert keinen Posteingang")
        XCTAssertTrue(refused.text.contains("mail index locked"))
        let link = InboxText.failure(message: "Nicht verbunden: getrennt", remote: false)
        XCTAssertEqual(link.title, "Posteingang nicht geladen")
        XCTAssertFalse(link.missing)
        // unknown rpc ohne Antwort des Gateways ist kein Befund über das Gateway
        XCTAssertFalse(InboxText.failure(message: "unknown rpc", remote: false).missing)
    }

    func testSourceFailure() {
        let broken = InboxFeed(items: [], mailError: "[Errno 2] No such file or directory")
        XCTAssertEqual(InboxText.sourceFailure(broken)?.title, InboxText.missingTitle)
        XCTAssertTrue(InboxText.sourceFailure(broken)?.text.contains("No such file") ?? false)
        let partial = InboxFeed(items: [InboxItem(kind: .chat, itemID: "a|b")], mailError: "kaputt")
        XCTAssertNil(InboxText.sourceFailure(partial))
        XCTAssertNil(InboxText.sourceFailure(InboxFeed(items: [], messagesError: "bridge offline")))
    }

    func testAddressAndInitials() {
        XCTAssertEqual(InboxText.address("\"Muster, Anna\" <Anna@Example.org>"), "anna@example.org")
        XCTAssertEqual(InboxText.address(" Info@Example.org "), "info@example.org")
        XCTAssertEqual(InboxText.initials("Anna Muster"), "AM")
        XCTAssertEqual(InboxText.initials("rundbrief@example.org"), "R")
        XCTAssertEqual(InboxText.initials("To Carla Beispiel"), "CB")
        XCTAssertEqual(InboxText.initials("Dr. Jens-Peter Beispiel"), "DJ")
        XCTAssertEqual(InboxText.initials("  "), "?")
        XCTAssertEqual(InboxText.initials("?"), "?")
    }

    func testDays() {
        let t = noon.timeIntervalSince1970
        let items = [
            InboxItem(kind: .mail, itemID: "1", ts: t - 3600),
            InboxItem(kind: .mail, itemID: "2", ts: t - 7200),
            InboxItem(kind: .mail, itemID: "3", ts: t - 86400),
            InboxItem(kind: .mail, itemID: "4", ts: 0),
            InboxItem(kind: .mail, itemID: "5", ts: t - 3 * 86400),
            InboxItem(kind: .mail, itemID: "6", ts: t - 400 * 86400),
        ]
        let days = InboxText.days(items, now: noon, timeZone: utc)
        XCTAssertEqual(days.map { $0.label }, ["Heute", "Gestern", "Do., 19. November", "Sa., 18. Oktober 2025", "Ohne Datum"])
        XCTAssertEqual(days[0].items.map { $0.itemID }, ["1", "2"])
        XCTAssertEqual(days[0].day, "2026-11-22")
        XCTAssertEqual(days[4].items.map { $0.itemID }, ["4"])
        XCTAssertEqual(InboxText.days([], now: noon, timeZone: utc), [])
    }

    func testDaysFollowTheTimeZone() {
        // 23:30 UTC ist in Berlin schon der nächste Tag
        let late = InboxItem(kind: .mail, itemID: "1", ts: noon.timeIntervalSince1970 - 12.5 * 3600)
        XCTAssertEqual(InboxText.days([late], now: noon, timeZone: utc)[0].label, "Gestern")
        XCTAssertEqual(InboxText.days([late], now: noon, timeZone: TimeZone(identifier: "Europe/Berlin")!)[0].label, "Heute")
    }

    func testWhenAndEmpty() {
        let t = noon.timeIntervalSince1970
        XCTAssertEqual(InboxText.when(t - 3 * 3600 + 300, now: noon, timeZone: utc), "Heute, 09:05")
        XCTAssertEqual(InboxText.when(t - 6 * 86400, now: noon, timeZone: utc), "Mo., 16. November, 12:00")
        XCTAssertEqual(InboxText.when(0, now: noon, timeZone: utc), "")
        XCTAssertEqual(InboxText.empty(days: 7), "Nichts in den letzten 7 Tagen.")
    }

    func testSeen() {
        let t = noon.timeIntervalSince1970
        let new = InboxItem(kind: .mail, itemID: "1", ts: t - 60)
        let old = InboxItem(kind: .mail, itemID: "2", ts: t - 7200)
        let chat = InboxItem(kind: .chat, itemID: "a|b", ts: t - 60)
        let since = t - 3600
        XCTAssertTrue(InboxSeen.isNew(new, since: since, opened: []))
        XCTAssertFalse(InboxSeen.isNew(new, since: since, opened: ["1"]))
        XCTAssertFalse(InboxSeen.isNew(old, since: since, opened: []))
        XCTAssertFalse(InboxSeen.isNew(chat, since: since, opened: []))
        XCTAssertEqual(InboxSeen.newCount([new, old, chat], since: since, opened: []), 1)
        XCTAssertEqual(InboxSeen.firstSince(now: t), t - 86400)
        XCTAssertEqual(InboxSeen.prune(["1", "9"], feed: [new, old]), ["1"])
    }
}

final class DayTextTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    func testKeyAndClock() {
        XCTAssertEqual(DayText.key(ts: 1_795_348_800, timeZone: utc), "2026-11-22")
        XCTAssertEqual(DayText.clock(ts: 1_795_348_800 + 5 * 60, timeZone: utc), "12:05")
        XCTAssertEqual(DayText.clock(ts: 1_795_348_800, timeZone: TimeZone(identifier: "Europe/Berlin")!), "13:00")
    }

    func testAdd() {
        XCTAssertEqual(DayText.add("2026-11-30", 1), "2026-12-01")
        XCTAssertEqual(DayText.add("2026-01-01", -1), "2025-12-31")
        XCTAssertEqual(DayText.add("2028-02-28", 1), "2028-02-29")
        XCTAssertEqual(DayText.add("2026-03-28", 2), "2026-03-30") // über die Zeitumstellung
        XCTAssertEqual(DayText.add("kaputt", 1), "kaputt")
    }

    func testLabels() {
        XCTAssertEqual(DayText.weekday("2026-11-22"), "So.")
        XCTAssertEqual(DayText.weekday("2026-11-23"), "Mo.")
        XCTAssertEqual(DayText.dayNumber("2026-11-05"), "5")
        XCTAssertEqual(DayText.label("2026-11-22", today: "2026-11-22"), "Heute")
        XCTAssertEqual(DayText.label("2026-11-21", today: "2026-11-22"), "Gestern")
        XCTAssertEqual(DayText.label("2026-11-23", today: "2026-11-22"), "Morgen")
        XCTAssertEqual(DayText.label("2026-11-25", today: "2026-11-22"), "Mi., 25. November")
        XCTAssertEqual(DayText.label("2027-01-02", today: "2026-11-22"), "Sa., 2. Januar 2027")
        XCTAssertNil(DayText.parts("2026-13-01"))
        XCTAssertEqual(DayText.parts("2026-11-22 09:30")?.day, 22)
    }
}
