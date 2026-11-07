import XCTest
@testable import RelayCore

final class DriveTests: XCTestCase {
    private func item(_ ref: String, _ id: String = "R1", rec: String = "ja") -> DriveItem {
        DriveItem(ref: ref, question: AgentQuestion(agent: "relay-ios", id: id, question: "Soll ich die alte Route löschen?",
                                                    context: "Seit 2024 ungenutzt.", recommendation: rec))
    }

    private func said(_ e: [DriveEffect]) -> [String] {
        e.compactMap { if case .say(let t) = $0 { return t } else { return nil } }
    }

    func testWordsWhileAnswering() {
        XCTAssertEqual(DriveText.forQuestion("Ja."), .accept)
        XCTAssertEqual(DriveText.forQuestion("ja bitte"), .accept)
        XCTAssertEqual(DriveText.forQuestion("Okay"), .accept)
        XCTAssertEqual(DriveText.forQuestion("Nein"), .decline)
        XCTAssertEqual(DriveText.forQuestion("nein danke"), .decline)
        XCTAssertEqual(DriveText.forQuestion("Wie bitte?"), .repeatQuestion)
        XCTAssertEqual(DriveText.forQuestion("später"), .skip)
        XCTAssertEqual(DriveText.forQuestion("Stopp"), .stop)
        XCTAssertEqual(DriveText.forQuestion("  "), .silence)
        // ein ganzer Satz ist eine Antwort, auch wenn er mit „nein“ beginnt
        XCTAssertEqual(DriveText.forQuestion("Nein, erst nach dem Backup."), .answer("Nein, erst nach dem Backup."))
    }

    func testWordsWhileConfirming() {
        XCTAssertEqual(DriveText.forConfirm("Senden"), .send)
        XCTAssertEqual(DriveText.forConfirm("ja"), .send)
        XCTAssertEqual(DriveText.forConfirm("passt"), .send)
        XCTAssertEqual(DriveText.forConfirm("nochmal"), .retry)
        XCTAssertEqual(DriveText.forConfirm("nein"), .retry)
        XCTAssertEqual(DriveText.forConfirm("Falsch"), .retry)
        XCTAssertEqual(DriveText.forConfirm("überspringen"), .skip)
        XCTAssertEqual(DriveText.forConfirm("beenden"), .stop)
        XCTAssertEqual(DriveText.forConfirm(""), .silence)
        XCTAssertEqual(DriveText.forConfirm("erst morgen früh"), .answer("erst morgen früh"))
    }

    func testPromptReadsQuestionAndRecommendationOnly() {
        let q = item("a", rec: "Löschen, die Route ist tot").question
        let p = DriveText.prompt(q, index: 0, total: 2, hint: true)
        XCTAssertTrue(p.hasPrefix("Rückfrage 1 von 2, von relay-ios."))
        XCTAssertTrue(p.contains("Soll ich die alte Route löschen?"))
        XCTAssertTrue(p.contains("Empfehlung: Löschen, die Route ist tot"))
        XCTAssertFalse(p.contains("2024"), "der Kontext wird nicht vorgelesen")
        XCTAssertTrue(p.contains("Sag ja, nein oder deine Antwort."))
        let single = DriveText.prompt(q, index: 0, total: 1, hint: false)
        XCTAssertTrue(single.hasPrefix("Rückfrage von relay-ios."))
        XCTAssertFalse(single.contains("Sag ja"))
        let noRec = DriveText.prompt(item("b", rec: "").question, index: 0, total: 1, hint: true)
        XCTAssertTrue(noRec.hasSuffix("Sag deine Antwort."))
    }

    func testConfirmPrompt() {
        let q = item("a", rec: "Löschen").question
        XCTAssertEqual(DriveText.confirmPrompt("ja", question: q), "Ich antworte: ja, also Löschen. Senden?")
        XCTAssertEqual(DriveText.confirmPrompt("ja", question: item("b", rec: "ja").question), "Ich antworte: ja. Senden oder nochmal?")
        XCTAssertEqual(DriveText.confirmPrompt("erst morgen", question: q), "Ich antworte: erst morgen. Senden oder nochmal?")
    }

    func testAnswerConfirmSend() {
        var d = DriveSession()
        let e = d.start([item("a"), item("b", "R2")])
        XCTAssertEqual(d.phase, .answering)
        XCTAssertEqual(e.last, .listen)
        XCTAssertTrue(said(e)[0].hasPrefix("Rückfrage 1 von 2"))

        let c = d.heard("Ja")
        XCTAssertEqual(d.phase, .confirming("ja"))
        XCTAssertEqual(c.last, .listen)

        XCTAssertEqual(d.heard("senden"), [.send(ref: "a", text: "ja")])
        XCTAssertEqual(d.phase, .sending("ja"))

        let n = d.sent(error: nil)
        XCTAssertEqual(said(n).first, DriveText.sent)
        XCTAssertTrue(said(n)[1].hasPrefix("Rückfrage 2 von 2"))
        XCTAssertFalse(said(n)[1].contains("Sag ja"), "der Hinweis kommt nur beim ersten Mal")
        XCTAssertEqual(d.current?.ref, "b")
        XCTAssertEqual(n.last, .listen)
    }

    func testCorrectBeforeSending() {
        var d = DriveSession()
        _ = d.start([item("a")])
        _ = d.heard("erst nach dem Bäckup")
        XCTAssertEqual(d.phase, .confirming("erst nach dem Bäckup"))
        // „nochmal“: neu sprechen
        XCTAssertEqual(d.heard("nochmal"), [.say("Deine Antwort?"), .listen])
        XCTAssertEqual(d.phase, .answering)
        _ = d.heard("erst nach dem Backup")
        // oder gleich die richtige Antwort sagen: sie ersetzt die alte
        _ = d.heard("erst nach dem Backup von heute")
        XCTAssertEqual(d.phase, .confirming("erst nach dem Backup von heute"))
        XCTAssertEqual(d.heard("passt"), [.send(ref: "a", text: "erst nach dem Backup von heute")])
    }

    func testSendFailureKeepsAnswer() {
        var d = DriveSession()
        _ = d.start([item("a")])
        _ = d.heard("nein")
        _ = d.heard("senden")
        let e = d.sent(error: "Nicht verbunden.")
        XCTAssertEqual(d.phase, .confirming("nein"))
        XCTAssertTrue(said(e)[0].contains("Nicht gesendet. Nicht verbunden."))
        XCTAssertEqual(d.command(.send), [.send(ref: "a", text: "nein")])
        let done = d.sent(error: nil)
        XCTAssertEqual(said(done), [DriveText.sent, DriveText.allDone])
        XCTAssertEqual(d.phase, .waiting)
    }

    func testSkipRepeatAndStop() {
        var d = DriveSession()
        _ = d.start([item("a"), item("b", "R2")])
        let r = d.heard("wiederholen")
        XCTAssertTrue(said(r)[0].hasPrefix("Rückfrage 1 von 2"))
        let s = d.heard("überspringen")
        XCTAssertEqual(said(s)[0], DriveText.skipped)
        XCTAssertEqual(d.current?.ref, "b")
        XCTAssertEqual(d.heard("stopp"), [.say(DriveText.stopped)])
        XCTAssertEqual(d.phase, .stopped)
        XCTAssertEqual(d.heard("ja"), [])
        XCTAssertEqual(d.enqueue([item("c", "R3")]), [], "beendet: nichts mehr vorlesen")
    }

    func testSilencePausesAfterTwice() {
        var d = DriveSession()
        _ = d.start([item("a")])
        let once = d.heard("")
        XCTAssertEqual(said(once)[0], DriveText.notHeard)
        XCTAssertEqual(once.last, .listen)
        XCTAssertEqual(d.heard(""), [.say(DriveText.paused)])
        XCTAssertEqual(d.phase, .paused)
        XCTAssertEqual(d.command(.silence), [])
        let back = d.resume()
        XCTAssertEqual(d.phase, .answering)
        XCTAssertEqual(back.last, .listen)
    }

    func testWaitingReadsNewQuestions() {
        var d = DriveSession()
        XCTAssertEqual(d.start([]), [.say(DriveText.nothingOpen)])
        XCTAssertEqual(d.phase, .waiting)
        let e = d.enqueue([item("a")])
        XCTAssertEqual(d.phase, .answering)
        XCTAssertTrue(said(e)[0].hasPrefix("Rückfrage von relay-ios."))
        // dieselbe noch einmal: nichts Neues
        XCTAssertEqual(d.enqueue([item("a")]), [])
        // eine weitere während des Beantwortens wartet in der Schlange
        XCTAssertEqual(d.enqueue([item("b", "R2")]), [])
        XCTAssertEqual(d.queue.map(\.ref), ["a", "b"])
    }

    func testAnsweredElsewhere() {
        var d = DriveSession()
        _ = d.start([item("a"), item("b", "R2")])
        // die zweite wird am PC beantwortet: still raus
        XCTAssertEqual(d.drop(ref: "b"), [])
        XCTAssertEqual(d.queue.map(\.ref), ["a"])
        // die gerade vorgelesene: Hinweis, dann fertig
        XCTAssertEqual(said(d.drop(ref: "a")), [DriveText.answeredElsewhere, DriveText.allDone])
        XCTAssertEqual(d.phase, .waiting)
        XCTAssertEqual(d.enqueue([item("a")]), [], "erledigt kommt nicht wieder")
    }

    func testDropWhileSendingKeepsNext() {
        var d = DriveSession()
        _ = d.start([item("a"), item("b", "R2")])
        _ = d.heard("ja")
        _ = d.heard("senden")
        // das Speichern der Antwort meldet „a“ als beantwortet, bevor das Senden zurückkommt
        XCTAssertEqual(d.drop(ref: "a"), [])
        _ = d.sent(error: nil)
        XCTAssertEqual(d.current?.ref, "b")
        XCTAssertEqual(d.phase, .answering)
    }

    func testOpenQueueFromNotices() {
        let n1 = Notice(ref: "s2", ts: 20, title: "", text: "Weiter?", source: "", tag: "rueckfrage:a:R2")
        let n2 = Notice(ref: "s1", ts: 10, title: "", text: "Löschen?", source: "", tag: "rueckfrage:a:R1")
        let done = Notice(ref: "s3", ts: 5, title: "", text: "Alt?", source: "", tag: "rueckfrage:a:R0", answer: "ja")
        let report = Notice(ref: "s4", ts: 1, title: "", text: "Fertig", source: "", tag: "meldung:a:M1")
        let plain = Notice(ref: "s5", ts: 2, title: "Backup", text: "Login", source: "", tag: "backup")
        XCTAssertEqual(DriveQueue.open([n1, n2, done, report, plain]).map(\.ref), ["s1", "s2"])
    }

    // MARK: Gespräch mit einer Sitzung

    func testTalkRoundTrip() {
        var t = DriveTalk(key: "c1:x", name: "webapp")
        XCTAssertEqual(t.start(), [.say("Gespräch mit webapp. Was soll ich sagen?"), .listen])
        XCTAssertEqual(t.heard("Lass die Tests laufen"), [.say("An webapp: Lass die Tests laufen. Senden oder nochmal?"), .listen])
        XCTAssertEqual(t.phase, .confirming("Lass die Tests laufen"))
        XCTAssertEqual(t.heard("senden"), [.send("Lass die Tests laufen")])
        XCTAssertEqual(t.sent(error: nil), [.say(DriveTalk.waiting), .awaitReply])
        XCTAssertEqual(t.phase, .working)
        XCTAssertEqual(t.heard("ja"), [], "während die Sitzung arbeitet, zählt nichts Gehörtes")
        XCTAssertEqual(t.replied("Alle 42 Tests sind grün."), [.say("Alle 42 Tests sind grün."), .listen])
        XCTAssertEqual(t.phase, .dictating)
        XCTAssertEqual(t.heard("danke"), [.say(DriveTalk.ended)])
        XCTAssertFalse(t.isActive)
    }

    func testTalkCorrectAndFail() {
        var t = DriveTalk(key: "k", name: "api")
        _ = t.start()
        _ = t.heard("mach den Bild")
        XCTAssertEqual(t.heard("nochmal"), [.say(DriveTalk.again), .listen])
        _ = t.heard("mach den Build")
        // ein neuer Satz statt „senden“ ersetzt den Text
        _ = t.heard("mach den Build und dann die Tests")
        XCTAssertEqual(t.phase, .confirming("mach den Build und dann die Tests"))
        XCTAssertEqual(t.command(.send), [.send("mach den Build und dann die Tests")])
        let e = t.sent(error: "Nicht verbunden.")
        XCTAssertEqual(t.phase, .confirming("mach den Build und dann die Tests"))
        XCTAssertEqual(e.last, .listen)
        _ = t.heard("senden")
        _ = t.sent(error: nil)
        XCTAssertEqual(t.replied(nil), [.say(DriveTalk.noReply("api"))])
        XCTAssertEqual(t.phase, .ended)
    }

    func testTalkSilenceEnds() {
        var t = DriveTalk(key: "k", name: "api")
        _ = t.start()
        XCTAssertEqual(t.heard("").last, .listen)
        XCTAssertEqual(t.heard(""), [.say(DriveTalk.ended)])
        XCTAssertEqual(t.phase, .ended)
    }

    func testSpokenReply() {
        let long = "Erledigt. Die Datei `docs/nachtlog.md` ist ergänzt.\n\n```swift\nlet x = 1\n```\n\nSiehe https://example.com für mehr."
        let r = DriveTalk.spokenReply(summary: nil, lastMessage: long, question: nil)
        XCTAssertTrue(r.hasPrefix("Erledigt. Die Datei nachtlog.md ist ergänzt."))
        XCTAssertFalse(r.contains("let x"))
        XCTAssertFalse(r.contains("docs/"))
        XCTAssertEqual(DriveTalk.spokenReply(summary: "Tests grün.", lastMessage: long, question: nil), "Tests grün.")
    }
}
