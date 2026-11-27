import XCTest
@testable import RelayCore

final class DraftsTests: XCTestCase {
    func testKeys() {
        XCTAssertEqual(Drafts.session("claude:c1:abc"), "session:claude:c1:abc")
        XCTAssertEqual(Drafts.question("R12"), "question:R12")
        XCTAssertNotEqual(Drafts.jarvis, Drafts.vault)
        XCTAssertNotEqual(Drafts.jarvis, Drafts.report)
        XCTAssertNotEqual(Drafts.session("a"), Drafts.session("b"))
        XCTAssertNotEqual(Drafts.session("x"), Drafts.question("x"))
    }

    func testKind() {
        XCTAssertEqual(Drafts.kind(Drafts.jarvis), "jarvis")
        XCTAssertEqual(Drafts.kind(Drafts.vault), "vault")
        XCTAssertEqual(Drafts.kind(Drafts.report), "fehlermeldung")
        XCTAssertEqual(Drafts.kind(Drafts.session("claude:c1:abc")), "sitzung")
        XCTAssertEqual(Drafts.kind(Drafts.question("R12")), "rückfrage")
    }

    func testCombined() {
        XCTAssertEqual(Drafts.combined(typed: "Hallo", heard: ""), "Hallo")
        XCTAssertEqual(Drafts.combined(typed: "", heard: "ich bin im Auto"), "ich bin im Auto")
        XCTAssertEqual(Drafts.combined(typed: "Hallo", heard: "ich bin im Auto"), "Hallo ich bin im Auto")
        XCTAssertEqual(Drafts.combined(typed: "Hallo ", heard: "ich bin im Auto"), "Hallo ich bin im Auto")
        XCTAssertEqual(Drafts.combined(typed: "Hallo\n", heard: " ich bin im Auto "), "Hallo\nich bin im Auto")
        XCTAssertEqual(Drafts.combined(typed: "  ", heard: "nur das"), "nur das")
        // kein Diktat: das Feld bleibt genau, wie es ist
        XCTAssertEqual(Drafts.combined(typed: "Hallo ", heard: "  "), "Hallo ")
    }

    func testRestore() {
        XCTAssertEqual(Drafts.restore(field: "", stored: "Entwurf"), "Entwurf")
        // ein Feld, in dem schon etwas steht, wird nicht überschrieben
        XCTAssertNil(Drafts.restore(field: "neu getippt", stored: "Entwurf"))
        XCTAssertNil(Drafts.restore(field: "", stored: ""))
        XCTAssertNil(Drafts.restore(field: "", stored: " \n"))
    }

    func testSetGetRemove() {
        var b = DraftBook()
        XCTAssertEqual(b.text(Drafts.jarvis), "")
        XCTAssertTrue(b.set(Drafts.jarvis, "Was läuft", now: 100))
        XCTAssertEqual(b.text(Drafts.jarvis), "Was läuft")
        // derselbe Text noch einmal: nichts zu schreiben
        XCTAssertFalse(b.set(Drafts.jarvis, "Was läuft", now: 200))
        XCTAssertEqual(b.entries[Drafts.jarvis]?.ts, 100)
        XCTAssertTrue(b.set(Drafts.jarvis, "Was läuft gerade?", now: 300))
        XCTAssertEqual(b.entries[Drafts.jarvis]?.ts, 300)
        XCTAssertTrue(b.remove(Drafts.jarvis))
        XCTAssertFalse(b.remove(Drafts.jarvis))
        XCTAssertTrue(b.isEmpty)
    }

    /// Nach dem Senden ist das Feld leer: Der Entwurf ist weg.
    func testEmptyTextRemoves() {
        var b = DraftBook()
        b.set(Drafts.session("s1"), "Antwort", now: 1)
        XCTAssertTrue(b.set(Drafts.session("s1"), "", now: 2))
        XCTAssertEqual(b.text(Drafts.session("s1")), "")
        XCTAssertTrue(b.isEmpty)
        b.set(Drafts.session("s1"), "Antwort", now: 3)
        XCTAssertTrue(b.set(Drafts.session("s1"), "  \n ", now: 4))
        XCTAssertTrue(b.isEmpty)
        // ein leeres Feld ohne Entwurf: nichts zu schreiben
        XCTAssertFalse(b.set(Drafts.session("s1"), "", now: 5))
    }

    func testEachFieldHasItsOwnDraft() {
        var b = DraftBook()
        b.set(Drafts.jarvis, "an Jarvis", now: 1)
        b.set(Drafts.session("s1"), "an Sitzung eins", now: 1)
        b.set(Drafts.session("s2"), "an Sitzung zwei", now: 1)
        b.set(Drafts.question("R1"), "Ja, aber", now: 1)
        b.set(Drafts.session("s1"), "", now: 2)
        XCTAssertEqual(b.text(Drafts.jarvis), "an Jarvis")
        XCTAssertEqual(b.text(Drafts.session("s1")), "")
        XCTAssertEqual(b.text(Drafts.session("s2")), "an Sitzung zwei")
        XCTAssertEqual(b.text(Drafts.question("R1")), "Ja, aber")
    }

    /// Der Text bleibt zeichengenau, auch Leerzeichen am Ende und Zeilenumbrüche.
    func testTextIsKeptVerbatim() {
        var b = DraftBook()
        let text = "Erste Zeile\n\nzweite mit „Anführung“ und Emoji 🚗 "
        b.set(Drafts.jarvis, text, now: 1)
        XCTAssertEqual(b.text(Drafts.jarvis), text)
        let back = DraftBook.decode(b.encode() ?? Data())
        XCTAssertEqual(back, b)
        XCTAssertEqual(back.text(Drafts.jarvis), text)
    }

    func testIgnoresEmptyKeyAndHugeText() {
        var b = DraftBook()
        XCTAssertFalse(b.set("", "Text", now: 1))
        XCTAssertFalse(b.set(Drafts.jarvis, String(repeating: "a", count: DraftBook.maxLength + 1), now: 1))
        XCTAssertTrue(b.isEmpty)
        XCTAssertTrue(b.set(Drafts.jarvis, String(repeating: "a", count: DraftBook.maxLength), now: 1))
    }

    func testDecodeBrokenFileGivesEmptyBook() {
        XCTAssertTrue(DraftBook.decode(Data()).isEmpty)
        XCTAssertTrue(DraftBook.decode(Data("kein json".utf8)).isEmpty)
        XCTAssertTrue(DraftBook.decode(Data("[1,2]".utf8)).isEmpty)
    }

    func testPruneByAge() {
        var b = DraftBook()
        let now = 10_000_000.0
        b.set(Drafts.session("alt"), "liegt lange", now: now - DraftBook.maxAge - 10)
        b.set(Drafts.session("frisch"), "von gestern", now: now - 86400)
        XCTAssertTrue(b.prune(now: now))
        XCTAssertEqual(b.text(Drafts.session("alt")), "")
        XCTAssertEqual(b.text(Drafts.session("frisch")), "von gestern")
        XCTAssertFalse(b.prune(now: now))
    }

    func testPruneByCountKeepsNewest() {
        var b = DraftBook()
        for i in 0..<(DraftBook.maxCount + 5) { b.set(Drafts.session("s\(i)"), "Text \(i)", now: Double(1000 + i)) }
        XCTAssertTrue(b.prune(now: 2000))
        XCTAssertEqual(b.entries.count, DraftBook.maxCount)
        XCTAssertEqual(b.text(Drafts.session("s0")), "")
        XCTAssertEqual(b.text(Drafts.session("s4")), "")
        XCTAssertEqual(b.text(Drafts.session("s5")), "Text 5")
        XCTAssertEqual(b.text(Drafts.session("s\(DraftBook.maxCount + 4)")), "Text \(DraftBook.maxCount + 4)")
    }
}
