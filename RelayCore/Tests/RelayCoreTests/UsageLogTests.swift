import XCTest
@testable import RelayCore

final class UsageLogTests: XCTestCase {
    private func ev(_ id: String, _ ts: Double, sent: Bool = false) -> UsageEvent {
        UsageEvent(id: id, ts: ts, screen: "chat", action: "gesendet", session: "c1-x", appVersion: "ios 0.3.8 (3)",
                   kind: "text", length: 12, sent: sent)
    }

    func testWireCarriesNoContentOnlyKindAndLength() {
        let w = ev("a", 100).wire
        XCTAssertEqual(w.str("id"), "a")
        XCTAssertEqual(w.str("screen"), "chat")
        XCTAssertEqual(w.str("action"), "gesendet")
        XCTAssertEqual(w.str("session"), "c1-x")
        XCTAssertEqual(w.str("app_version"), "ios 0.3.8 (3)")
        XCTAssertEqual(w.str("kind"), "text")
        XCTAssertEqual(w["length"].int, 12)
        XCTAssertTrue(w["sent"].isNull)
        XCTAssertTrue(w["text"].isNull)
    }

    func testPendingAndMarkSent() {
        var b = UsageBuffer()
        for i in 0..<5 { b.append(ev("e\(i)", Double(i))) }
        XCTAssertEqual(b.pendingCount, 5)
        XCTAssertEqual(b.pending(limit: 2).map(\.id), ["e0", "e1"])
        b.markSent(["e0", "e1"])
        XCTAssertEqual(b.pendingCount, 3)
        XCTAssertEqual(b.pending().map(\.id), ["e2", "e3", "e4"])
    }

    func testConnectionLossKeepsEventsForTheNextTry() {
        // Senden bricht ab (keine Bestätigung): nichts wird als gesendet markiert, der nächste Versuch nimmt dieselben.
        var b = UsageBuffer()
        for i in 0..<3 { b.append(ev("e\(i)", Double(i))) }
        let first = b.pending()
        // ... rpc wirft, markSent wird nicht aufgerufen ...
        b.append(ev("e3", 3))
        XCTAssertEqual(b.pending().map(\.id), first.map(\.id) + ["e3"])
        let p = UsageBuffer.putParams(b.pending())
        XCTAssertEqual(p["items"].array.count, 4)
        XCTAssertEqual(p["items"][0].str("id"), "e0")
    }

    func testRetentionDropsOldEventsEvenUnsent() {
        var b = UsageBuffer()
        let now = 100 * 86400.0
        b.append(ev("alt", now - 31 * 86400))
        b.append(ev("altGesendet", now - 40 * 86400, sent: true))
        b.append(ev("neu", now - 29 * 86400))
        b.prune(now: now)
        XCTAssertEqual(b.events.map(\.id), ["neu"])
    }

    func testCapDropsSentFirst() {
        var b = UsageBuffer()
        for i in 0..<UsageBuffer.maxEvents { b.append(ev("e\(i)", Double(i), sent: i < 10)) }
        b.append(ev("neu", 1e6))
        XCTAssertEqual(b.events.count, UsageBuffer.maxEvents)
        XCTAssertFalse(b.events.contains { $0.id == "e0" })
        XCTAssertTrue(b.events.contains { $0.id == "e10" })
        XCTAssertEqual(b.events.last?.id, "neu")
    }

    func testBufferSurvivesEncoding() throws {
        var b = UsageBuffer()
        b.append(ev("a", 1)); b.append(ev("b", 2, sent: true))
        let d = try JSONEncoder().encode(b)
        XCTAssertEqual(try JSONDecoder().decode(UsageBuffer.self, from: d), b)
    }

    func testRecentContentKeepsOnlyTheLastMinutes() {
        var c = RecentContent()
        c.add(ts: 0, screen: "chat", session: "s", kind: "text", text: "alt")
        c.add(ts: 500, screen: "chat", session: "s", kind: "diktat", text: "mittel")
        c.add(ts: 700, screen: "chat", session: nil, kind: "text", text: "  neu  ")
        c.add(ts: 701, screen: "chat", session: nil, kind: "text", text: "   ")
        XCTAssertEqual(c.entries.map(\.text), ["mittel", "neu"])
        XCTAssertEqual(c.wire(now: 1150).array.map { $0.str("text") }, ["neu"])
    }

    func testReportSendsContentsOnlyWithTheCheckmark() {
        var b = UsageBuffer()
        b.append(ev("vorher", 0))
        b.append(ev("jetzt", 1000))
        var c = RecentContent()
        c.add(ts: 990, screen: "chat", session: "c1-x", kind: "text", text: "Hallo")
        let without = UsageReport.params(text: " Senden hängt ", buffer: b, contents: nil, appVersion: "ios 0.3.8 (3)", now: 1000)
        XCTAssertEqual(without.str("text"), "Senden hängt")
        XCTAssertEqual(without["events"].array.map { $0.str("id") }, ["jetzt"])
        XCTAssertTrue(without["contents"].isNull)
        let with = UsageReport.params(text: "x", buffer: b, contents: c, appVersion: "ios 0.3.8 (3)", now: 1000)
        XCTAssertEqual(with["contents"][0].str("text"), "Hallo")
        XCTAssertTrue(UsageReport.canSend("geht nicht"))
        XCTAssertFalse(UsageReport.canSend("  a "))
    }
}
