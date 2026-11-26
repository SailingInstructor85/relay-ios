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
        // ein Dokument ist kein Bild: kein Hinweis zum Ansehen und Einbinden
        XCTAssertFalse(p.contains("Ein Bild kann die Sitzung ansehen"))
    }

    func testAskParamsMarkUploads() {
        // Ein Upload ist als solcher gekennzeichnet: Das Gateway legt dafür immer einen neuen Vorgang an und verbucht
        // ihn nie als Antwort auf eine offene Rückfrage.
        let prompt = JarvisDocs.prompt(message: "", paths: ["/home/m/uploads/2026-11-26/536.pdf"], vault: "~/vault")
        let up = JarvisDocs.askParams(text: prompt, byVoice: false, upload: true)
        XCTAssertEqual(up["upload"], JSON.bool(true))
        XCTAssertEqual(up["text"], JSON.string(prompt))
        XCTAssertEqual(up["stream"], JSON.bool(true))
        XCTAssertEqual(up["source"], JSON.string("text"))
        // gesprochener Auftrag zu einem Anhang bleibt ein Upload
        let spoken = JarvisDocs.askParams(text: prompt, byVoice: true, upload: true)
        XCTAssertEqual(spoken["upload"], JSON.bool(true))
        XCTAssertEqual(spoken["source"], JSON.string("voice"))
        // getippter oder gesprochener Text ohne Anhang: kein Feld, er darf eine offene Rückfrage beantworten
        let typed = JarvisDocs.askParams(text: "Ja, wie bei 533", byVoice: false, upload: false)
        XCTAssertNil(typed["upload"])
        XCTAssertEqual(Set(typed.keys), ["text", "stream", "status", "source"])
        // jede Frage verlangt die Statuszeile „Chief hat es“
        XCTAssertEqual(typed["status"], JSON.bool(true))
        XCTAssertEqual(up["status"], JSON.bool(true))
        XCTAssertNil(JarvisDocs.askParams(text: "Ja", byVoice: true, upload: false)["upload"])
    }

    func testPromptForPictures() {
        let one = JarvisDocs.prompt(message: "Zur Bewerbung bei Muster legen", paths: ["/u/foto-1700000000.png"])
        XCTAssertTrue(one.hasPrefix("Martin gibt dir ein Bild vom iPhone (Foto oder Screenshot). Es liegt als Upload am PC:"))
        XCTAssertTrue(one.contains("Sein Auftrag dazu: Zur Bewerbung bei Muster legen"))
        XCTAssertTrue(one.contains("Ein Bild kann die Sitzung ansehen."))
        XCTAssertTrue(one.contains("bindet es in die Notiz ein"))
        let many = JarvisDocs.prompt(message: "", paths: ["/u/foto-1-1.jpg", "/u/foto-1-2.HEIC", "/u/zwischenablage-1.png"])
        XCTAssertTrue(many.hasPrefix("Martin gibt dir 3 Bilder vom iPhone (Fotos oder Screenshots). Sie liegen als Uploads am PC:"))
        XCTAssertTrue(many.contains("frage ihn, bevor du es weitergibst"))
    }

    func testHeadAndKinds() {
        XCTAssertEqual(JarvisDocs.head(count: 1, images: 0), "Martin gibt dir ein Dokument vom iPhone. Es liegt als Upload am PC:")
        XCTAssertEqual(JarvisDocs.head(count: 3, images: 0), "Martin gibt dir 3 Dokumente vom iPhone. Sie liegen als Uploads am PC:")
        XCTAssertTrue(JarvisDocs.isPicture("/u/zwischenablage-1700000000.png"))
        XCTAssertFalse(JarvisDocs.isPicture("/u/video-1700000000.mov"))
        XCTAssertFalse(JarvisDocs.isPicture("/u/brief.pdf"))
        XCTAssertEqual(JarvisDocs.clipboardName(stamp: 1700000000), "zwischenablage-1700000000.png")
        XCTAssertTrue(Attach.isImage(JarvisDocs.clipboardName(stamp: 1)))
        XCTAssertEqual(JarvisDocs.symbol("foto-1.jpg"), "photo")
        XCTAssertEqual(JarvisDocs.symbol("video-1.MOV"), "video")
        XCTAssertEqual(JarvisDocs.symbol("brief.pdf"), "doc")
    }

    func testPromptWithoutMessageAsksFirst() {
        let p = JarvisDocs.prompt(message: "  ", paths: ["/u/a.pdf", "/u/b.jpg"])
        XCTAssertTrue(p.hasPrefix("Martin gibt dir 2 Anhänge vom iPhone (Bilder und Dokumente). Sie liegen als Uploads am PC:"))
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
