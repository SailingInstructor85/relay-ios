import XCTest
@testable import RelayCore

final class JarvisDocsTests: XCTestCase {
    func testPromptWithMessage() {
        let p = JarvisDocs.prompt(message: " Bitte zur Steuer legen ", paths: ["/home/m/uploads/2026-11-24/brief.pdf"], vault: "~/vault")
        XCTAssertTrue(p.hasPrefix("Martin gibt dir ein Dokument vom iPhone."))
        XCTAssertTrue(p.contains("- /home/m/uploads/2026-11-24/brief.pdf"))
        XCTAssertTrue(p.contains("Sein Auftrag dazu: Bitte zur Steuer legen"))
        XCTAssertTrue(p.contains("im Ordner ~/vault"))
        XCTAssertFalse(p.contains("Er hat nichts dazu geschrieben"))
    }

    func testPromptWithoutMessageAsksFirst() {
        let p = JarvisDocs.prompt(message: "  ", paths: ["/u/a.pdf", "/u/b.jpg"])
        XCTAssertTrue(p.hasPrefix("Martin gibt dir 2 Dokumente vom iPhone."))
        XCTAssertTrue(p.contains("- /u/a.pdf\n- /u/b.jpg"))
        XCTAssertTrue(p.contains("frage ihn, bevor du es weitergibst"))
        XCTAssertFalse(p.contains("Sein Auftrag dazu"))
        // ohne Einstellung der Standardordner des Vaults
        XCTAssertTrue(p.contains(VaultDrop.defaultDir))
    }

    func testShown() {
        XCTAssertEqual(JarvisDocs.shown(message: "Wohin damit?", names: ["brief.pdf"]), "Wohin damit?\nAnhang: brief.pdf")
        XCTAssertEqual(JarvisDocs.shown(message: "", names: ["a.pdf", "b.jpg"]), "Anhänge: a.pdf, b.jpg")
        XCTAssertEqual(JarvisDocs.shown(message: " Hallo ", names: []), "Hallo")
    }

    func testCanSendAndProgress() {
        XCTAssertTrue(JarvisDocs.canSend(docs: 1, asking: false))
        XCTAssertFalse(JarvisDocs.canSend(docs: 0, asking: false))
        XCTAssertFalse(JarvisDocs.canSend(docs: 2, asking: true))
        XCTAssertEqual(JarvisDocs.progress(index: 0, count: 1, name: "a.pdf"), "Lade a.pdf hoch…")
        XCTAssertEqual(JarvisDocs.progress(index: 1, count: 3, name: "b.pdf"), "Lade 2/3 b.pdf hoch…")
    }
}
