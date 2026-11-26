import XCTest
@testable import RelayCore

final class JarvisOutboxTests: XCTestCase {
    private func item(_ id: String, key: String = JarvisOutbox.key, text: String = "Was läuft?", state: OutState = .queued,
                      tries: Int = 0, files: [String] = [], voice: Bool = false) -> OutItem {
        OutItem(id: id, key: key, text: text, at: 100, state: state, tries: tries, files: files, voice: voice)
    }

    func testSurvivesTheDiskWithItsJarvisFields() {
        let spoken = OutItem(id: "a", key: JarvisOutbox.key, text: "Auftrag mit Pfad", at: 5, voice: true, shown: "Bitte ablegen\nAnhang: brief.pdf", upload: true)
        let back = OutboxLogic.decode(OutboxLogic.encode([spoken, item("b")]))
        XCTAssertEqual(back, [spoken, item("b")])
        XCTAssertTrue(back[0].voice); XCTAssertTrue(back[0].upload); XCTAssertEqual(back[0].shown, "Bitte ablegen\nAnhang: brief.pdf")
        XCTAssertFalse(back[1].voice); XCTAssertNil(back[1].shown)
        // ein alter Eintrag ohne die neuen Felder (Sitzungs-Chat von 0.4.12) wird unverändert gelesen
        let old = Data(#"[{"id":"x","key":"claude:c1:s","text":"hi","at":1,"state":"queued","tries":0,"done_at":0,"force":false}]"#.utf8)
        XCTAssertEqual(OutboxLogic.decode(old), [OutItem(id: "x", key: "claude:c1:s", text: "hi", at: 1)])
        // ein Neustart der App: Die wartende Frage ist noch da
        XCTAssertEqual(OutboxLogic.restored(back).map(\.id), ["a", "b"])
    }

    func testNextKeepsTheOrderAndHoldsJarvisBack() {
        let chat = item("c", key: "claude:c1:s")
        let list = [item("j1"), chat, item("j2")]
        // im Vordergrund der Reihe nach
        XCTAssertEqual(JarvisOutbox.next(list, foreground: true, once: false, now: 100, lastStart: 0)?.id, "j1")
        // gerade ging eine Frage an Jarvis hinaus: die nächste wartet kurz, der Sitzungs-Chat nicht
        XCTAssertEqual(JarvisOutbox.next(list, foreground: true, once: false, now: 100, lastStart: 99)?.id, "c")
        XCTAssertEqual(JarvisOutbox.next([item("j1", state: .sending), item("j2")], foreground: true, once: false, now: 100, lastStart: 99)?.id, nil)
        XCTAssertEqual(JarvisOutbox.next([item("j1", state: .sending), item("j2")], foreground: true, once: false, now: 103, lastStart: 99)?.id, "j2")
        // im Hintergrund nur, wenn das Gateway doppelte Fragen erkennt
        XCTAssertEqual(JarvisOutbox.next(list, foreground: false, once: false, now: 100, lastStart: 0)?.id, "c")
        XCTAssertEqual(JarvisOutbox.next(list, foreground: false, once: true, now: 100, lastStart: 0)?.id, "j1")
        XCTAssertNil(JarvisOutbox.next([item("j1")], foreground: false, once: false, now: 100, lastStart: 0))
        XCTAssertNil(JarvisOutbox.next([item("j1", state: .failed)], foreground: true, once: true, now: 100, lastStart: 0))
    }

    func testNothingGoesOutTwiceWithoutTheGatewaysPromise() {
        // gar keine Verbindung: sicher nicht angekommen, der Versuch zählt nicht
        XCTAssertEqual(JarvisOutbox.outcome(remote: false, message: "Nicht verbunden: Kein Netz", once: false), .again(sent: false))
        let never = JarvisOutbox.failed(item("a", state: .sending, tries: 1), .again(sent: false), message: "Nicht verbunden: Kein Netz")
        XCTAssertEqual(never.state, .queued); XCTAssertEqual(never.tries, 0)
        XCTAssertFalse(JarvisOutbox.unclear(never, once: false))
        // die Verbindung riss beim Warten auf die Antwort: ohne Zusage bleibt die Nachricht stehen
        XCTAssertEqual(JarvisOutbox.outcome(remote: false, message: "Verbindung getrennt", once: false), .unclear)
        let open = JarvisOutbox.failed(item("a", state: .sending, tries: 1), .unclear, message: "Verbindung getrennt")
        XCTAssertEqual(open.state, .failed); XCTAssertEqual(open.error, JarvisOutbox.unclearText)
        XCTAssertEqual(JarvisOutbox.status(open, connected: true, network: true), JarvisOutbox.unclearText)
        // mit Zusage (ask_once) geht sie unter derselben Kennung noch einmal
        XCTAssertEqual(JarvisOutbox.outcome(remote: false, message: "Verbindung getrennt", once: true), .again(sent: true))
        let again = JarvisOutbox.failed(item("a", state: .sending, tries: 1), .again(sent: true), message: "Verbindung getrennt")
        XCTAssertEqual(again.state, .queued); XCTAssertEqual(again.tries, 1); XCTAssertEqual(again.id, "a")
        XCTAssertFalse(JarvisOutbox.unclear(again, once: true))
        // die App wurde beim Senden beendet: nach dem Neustart wartet die Nachricht wieder, ihr Ausgang ist offen
        let restored = OutboxLogic.restored([item("a", state: .sending, tries: 1)])[0]
        XCTAssertEqual(restored.state, .queued)
        XCTAssertTrue(JarvisOutbox.unclear(restored, once: false))
        XCTAssertFalse(JarvisOutbox.unclear(restored, once: true))
        // eine Absage des Gateways
        XCTAssertEqual(JarvisOutbox.outcome(remote: true, message: "text fehlt", once: true), .refused("text fehlt"))
        let no = JarvisOutbox.failed(item("a", state: .sending, tries: 1), .refused("text fehlt"), message: "text fehlt")
        XCTAssertEqual(JarvisOutbox.status(no, connected: true, network: true), "Nicht gesendet: text fehlt")
        // „Erneut senden“: neue Kennung, der Zähler beginnt neu, sonst bliebe sie ohne Zusage für immer stehen
        let retried = OutboxLogic.retried(open, force: nil, newId: "n")
        XCTAssertEqual(retried.id, "n"); XCTAssertEqual(retried.tries, 0); XCTAssertEqual(retried.state, .queued)
        XCTAssertFalse(JarvisOutbox.unclear(retried, once: false))
    }

    func testStatusLine() {
        XCTAssertEqual(JarvisOutbox.status(item("a"), connected: false, network: true), "wartet auf Verbindung")
        XCTAssertEqual(JarvisOutbox.status(item("a"), connected: false, network: false), "wartet auf Netz")
        XCTAssertEqual(JarvisOutbox.status(item("a"), connected: true, network: true), "sendet gleich…")
        XCTAssertEqual(JarvisOutbox.status(item("a", state: .sending), connected: true, network: true), "sendet…")
        XCTAssertEqual(JarvisOutbox.status(item("a", state: .sending), connected: true, network: true, taken: "Chief hat es"), "Chief hat es")
        XCTAssertTrue(JarvisOutbox.actionable(item("a")))
        XCTAssertFalse(JarvisOutbox.actionable(item("a", state: .sending)))
        XCTAssertTrue(JarvisOutbox.actionable(item("a", state: .failed)))
    }

    func testAttachmentsBecomeTheUploadPrompt() {
        let waiting = item("a", text: "Bitte ablegen", files: ["1a2b3c4d-brief.pdf", "5e6f7a8b-foto.jpg"], voice: true)
        XCTAssertEqual(JarvisOutbox.shownText(waiting), "Bitte ablegen\nAnhänge: brief.pdf, foto.jpg")
        XCTAssertTrue(JarvisOutbox.editable(waiting))
        XCTAssertNil(JarvisOutbox.params(waiting)["upload"])
        let up = JarvisOutbox.uploaded(waiting, paths: ["/home/dev/uploads/brief.pdf", "/home/dev/uploads/foto.jpg"], vault: "~/vault")
        XCTAssertTrue(up.files.isEmpty); XCTAssertTrue(up.upload); XCTAssertTrue(up.voice)
        XCTAssertEqual(up.id, "a"); XCTAssertEqual(up.at, 100)
        XCTAssertEqual(up.shown, "Bitte ablegen\nAnhänge: brief.pdf, foto.jpg")
        XCTAssertTrue(up.text.contains("/home/dev/uploads/brief.pdf")); XCTAssertTrue(up.text.contains("Sein Auftrag dazu: Bitte ablegen"))
        XCTAssertFalse(JarvisOutbox.editable(up))  // der Text ist jetzt der Auftrag mit Pfaden
        let p = JarvisOutbox.params(up)
        XCTAssertEqual(p["upload"], .bool(true)); XCTAssertEqual(p["client_id"], .string("a"))
        XCTAssertEqual(p["source"], .string("voice")); XCTAssertEqual(p["stream"], .bool(false)); XCTAssertEqual(p["status"], .bool(true))
        // nichts hochgeladen (Dateien fehlen): Der Text bleibt, die Verweise gehen
        let none = JarvisOutbox.uploaded(waiting, paths: [], vault: "")
        XCTAssertEqual(none.text, "Bitte ablegen"); XCTAssertTrue(none.files.isEmpty); XCTAssertFalse(none.upload)
        // nur ein Anhang ohne Text
        XCTAssertEqual(JarvisOutbox.shownText(item("b", text: "", files: ["1a2b3c4d-brief.pdf"])), "Anhang: brief.pdf")
    }

    func testAnswerLandsInTheHistoryOnce() {
        let id = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
        let t = JarvisOutbox.turn(item(id, voice: true), answer: " Vier Sitzungen laufen. ", now: 500)
        XCTAssertEqual(t.id, UUID(uuidString: id)); XCTAssertEqual(t.q, "Was läuft?"); XCTAssertEqual(t.a, "Vier Sitzungen laufen.")
        XCTAssertTrue(t.voice); XCTAssertEqual(t.ts, 500); XCTAssertNil(t.topic); XCTAssertEqual(t.ref, "ask:" + id)
        // dieselbe Antwort ein zweites Mal (doppelter Versand): steht nur einmal im Verlauf
        let stored = JarvisSay.adding(t, to: [])
        XCTAssertEqual(stored?.count, 1)
        XCTAssertNil(JarvisSay.adding(t, to: stored ?? []))
        // eine leere Antwort geht nicht verloren (der Verlauf behält nur Züge mit Antwort)
        let empty = JarvisOutbox.turn(item(id), answer: "", now: 1)
        XCTAssertEqual(JarvisHistory.trimmed([empty]).count, 1)
        // die offene Ansicht übernimmt sie über denselben Weg wie die Rückmeldungen des Chiefs
        XCTAssertEqual(JarvisSay.missing(in: [], stored: [t]), [t])
        XCTAssertEqual(JarvisSay.spoken(t), "Vier Sitzungen laufen.")
    }

    func testSpokenOnlyForSpokenQuestionsInTheForeground() {
        let spoken = JarvisOutbox.turn(item("a", voice: true), answer: "Ja.", now: 1)
        let typed = JarvisOutbox.turn(item("b"), answer: "Ja.", now: 1)
        let say = JarvisTurn(q: "", a: "Fertig.", voice: false, topic: "Zugverbindung", ref: "t1")
        XCTAssertTrue(JarvisOutbox.speaks(spoken, foreground: true))
        XCTAssertFalse(JarvisOutbox.speaks(spoken, foreground: false))
        XCTAssertFalse(JarvisOutbox.speaks(typed, foreground: true))
        XCTAssertTrue(JarvisOutbox.speaks(say, foreground: true))
    }
}
