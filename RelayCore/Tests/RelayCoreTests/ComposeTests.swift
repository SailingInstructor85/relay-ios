import XCTest
@testable import RelayCore

final class ComposeTests: XCTestCase {
    private func q(_ text: String, _ header: String, multi: Bool, _ labels: String...) -> Question {
        Question(text: text, header: header, options: labels.map { QOption(label: $0, description: "") }, multi: multi, count: 1, questions: [])
    }
    private func form(_ qs: Question...) -> Question {
        Question(text: qs[0].text, header: qs[0].header, options: qs[0].options, multi: qs[0].multi, count: qs.count, questions: qs)
    }
    private func k(_ names: String...) -> [Step] { names.map { .key($0) } }

    func testOneTapUsable() {
        let one = q("Which color?", "Color", multi: false, "Red", "Green", "Blue")
        XCTAssertTrue(AnswerKeys.usable(one))
        XCTAssertFalse(AnswerKeys.usable(Question(text: "x", header: "", options: one.options, multi: true, count: 1, questions: [])))
        XCTAssertFalse(AnswerKeys.usable(Question(text: "x", header: "", options: one.options, multi: false, count: 2, questions: [])))
        XCTAssertFalse(AnswerKeys.usable(nil))
        XCTAssertEqual(AnswerKeys.option(1), ["2"])
    }

    func testSendParamsNameTheQuestion() {
        let p = AnswerKeys.sendParams(key: "claude:c1:s1", index: 1, question: "Which color?")
        XCTAssertEqual(p.str("key"), "claude:c1:s1")
        XCTAssertEqual(p["keys"].array, ["2"])
        XCTAssertTrue(p.flag("force"))
        XCTAssertEqual(p.str("expect_question"), "Which color?")
        XCTAssertEqual(AnswerKeys.declineParams(key: "k", question: q("Q?", "", multi: false, "a"))["keys"].array, ["Escape"])
    }

    func testFormNeedsEveryQuestion() {
        let one = q("Which color?", "Color", multi: false, "Red", "Green")
        XCTAssertFalse(AnswerKeys.formUsable(one))
        XCTAssertTrue(AnswerKeys.formUsable(form(one)))
        let two = form(q("A?", "A", multi: false, "S", "M"), q("B?", "B", multi: true, "Ham"))
        XCTAssertTrue(AnswerKeys.formUsable(two))
        let cut = Question(text: two.text, header: "", options: two.options, multi: false, count: 2, questions: [two.questions[0]])
        XCTAssertFalse(AnswerKeys.formUsable(cut))
    }

    func testFormWithMultiFreeTextAndSingle() {
        let fruits = q("Which fruits?", "Fruit", multi: true, "Apple", "Pear", "Plum")
        let size = q("Which size?", "Size", multi: false, "Small", "Large")
        let drink = q("Which drink?", "Drink", multi: false, "Tea", "Coffee")
        let steps = AnswerKeys.steps([fruits, size, drink], [Pick(options: [2, 0], other: "Fig"), Pick(options: [1]), Pick(other: " Mate ")])
        XCTAssertEqual(steps, k("1", "3", "Down", "Down", "Down") + [.text("Fig")] + k("Down", "Enter", "2", "3") + [.text("Mate")] + k("Enter", "1"))
    }

    func testMultiAloneAndUnanswered() {
        let colors = q("Which colors?", "Colors", multi: true, "Red", "Green", "Blue")
        XCTAssertEqual(AnswerKeys.steps([colors], [Pick(options: [1, 2])]), k("2", "3", "Down", "Down", "Down", "Down", "Enter", "1"))
        XCTAssertEqual(AnswerKeys.steps([colors], [Pick(other: "Gold")]), k("Down", "Down", "Down") + [.text("Gold")] + k("Down", "Enter", "1"))
        XCTAssertNil(AnswerKeys.steps([colors], [Pick()]))
        let single = q("Which?", "", multi: false, "a", "b")
        XCTAssertEqual(AnswerKeys.steps([single], [Pick(other: "x")]), k("3") + [.text("x")] + k("Enter"))
        XCTAssertEqual(AnswerKeys.steps([single], [Pick(options: [1])]), k("2"))
        let p = AnswerKeys.stepsParams(key: "k", question: form(single), picks: [Pick(options: [0])])!
        XCTAssertEqual(p["steps"].array, ["1"])
        XCTAssertEqual(p.str("expect_question"), "Which?")
    }

    func testPick() {
        XCTAssertEqual(Pick().choose(1, multi: true).choose(2, multi: true).choose(1, multi: true).options, [2])
        XCTAssertEqual(Pick(options: [0]).choose(1, multi: false).options, [1])
        XCTAssertEqual(Pick(options: [0]).typing(multi: false), Pick(other: ""))
        XCTAssertEqual(Pick(options: [0]).typing(multi: true), Pick(options: [0], other: ""))
        XCTAssertEqual(Pick(other: "x").typing(multi: false).other, nil)
    }

    func testSlashChipsAndCatalog() {
        XCTAssertEqual(SlashChips.parse("/a  /b\n/c"), ["/a", "/b", "/c"])
        XCTAssertEqual(SlashChips.parse("  "), [])
        let all = SlashCatalog.forTool("claude", user: ["/compact", "/mine"])
        XCTAssertEqual(all.first, "/compact")
        XCTAssertEqual(all.filter { $0 == "/compact" }.count, 1)
        XCTAssertEqual(SlashCatalog.matches(all, "/co"), ["/compact", "/context", "/cost", "/config"])
        XCTAssertEqual(SlashCatalog.matches(all, "/model"), [])
        XCTAssertEqual(SlashCatalog.matches(all, "/model x"), [])
        XCTAssertEqual(SlashCatalog.matches(all, "hello"), [])
        XCTAssertEqual(SlashCatalog.matches(all, "/").count, 10)
    }

    func testQuickReplies() {
        XCTAssertEqual(QuickReplies.parse("Weiter|Ja|Status?"), ["Weiter", "Ja", "Status?"])
        XCTAssertEqual(QuickReplies.parse(" a | |a|b "), ["a", "b"])
        XCTAssertEqual(QuickReplies.parse((1...12).map(String.init).joined(separator: "|")).count, 8)
    }

    func testOutboxLogic() {
        XCTAssertEqual(OutboxLogic.wait(0), 20)
        XCTAssertEqual(OutboxLogic.wait(1), 40)
        XCTAssertEqual(OutboxLogic.wait(4), 300)
        XCTAssertEqual(OutboxLogic.wait(40), 300)
        XCTAssertFalse(OutboxLogic.retries(RelayError("session gone", remote: true)))
        XCTAssertTrue(OutboxLogic.retries(RelayError("send: Zeitüberschreitung")))
        XCTAssertTrue(OutboxLogic.retries(URLError(.timedOut)))
        XCTAssertTrue(OutboxLogic.isBusyRefusal("session is busy, use force"))
        XCTAssertFalse(OutboxLogic.isBusyRefusal("not found"))
    }

    func testOutboxStoreAndSweep() {
        let a = OutItem(id: "a", key: "claude:c1:s", text: "hallo", at: 1, state: .sending, tries: 1)
        let b = OutItem(id: "b", key: "claude:c1:s", text: "fertig", at: 2, state: .delivered, doneAt: 100)
        let c = OutItem(id: "c", key: "claude:c1:s", text: "nein", at: 3, state: .failed, error: "refused: x", force: true)
        let back = OutboxLogic.decode(OutboxLogic.encode([a, b, c]))
        XCTAssertEqual(back.count, 3)
        XCTAssertEqual(back[2].error, "refused: x")
        XCTAssertTrue(back[2].force)
        let restored = OutboxLogic.restored(back)
        XCTAssertEqual(restored.map(\.id), ["a", "c"])
        XCTAssertEqual(restored[0].state, .queued)
        XCTAssertEqual(OutboxLogic.next(restored)?.id, "a")
        XCTAssertEqual(OutboxLogic.sweep([a, b], seen: ["fertig "], now: 101).map(\.id), ["a"])
        XCTAssertEqual(OutboxLogic.sweep([a, b], seen: [], now: 101).map(\.id), ["a", "b"])
        XCTAssertEqual(OutboxLogic.sweep([a, b], seen: [], now: 100 + 601).map(\.id), ["a"])
        XCTAssertEqual(OutboxLogic.decode(Data("kaputt".utf8)), [])
        XCTAssertEqual(OutboxLogic.status(a, connected: false, network: true), "sendet…")
        XCTAssertEqual(OutboxLogic.status(OutItem(id: "q", key: "k", text: "t", at: 0), connected: false, network: true), "wartet auf Verbindung")
        XCTAssertEqual(OutboxLogic.status(c, connected: true, network: true), "Nicht gesendet: refused: x")
    }

    func testAttach() {
        XCTAssertTrue(Attach.isImage("IMG.JPG"))
        XCTAssertTrue(Attach.isImage("x", mime: "image/png"))
        XCTAssertFalse(Attach.isImage("a.pdf"))
        XCTAssertTrue(Attach.isVideo("clip.MOV"))
        XCTAssertTrue(Attach.needsResize(name: "p.jpg", width: 4000, height: 3000))
        XCTAssertFalse(Attach.needsResize(name: "p.jpg", width: 2048, height: 1000))
        XCTAssertFalse(Attach.needsResize(name: "anim.gif", width: 4000, height: 3000))
        XCTAssertFalse(Attach.needsResize(name: "v.mp4", width: 4000, height: 3000))
        XCTAssertTrue(Attach.targetSize(4000, 3000) == (2048, 1536))
        XCTAssertTrue(Attach.targetSize(3000, 4000) == (1536, 2048))
        XCTAssertTrue(Attach.targetSize(1000, 500) == (1000, 500))
        XCTAssertEqual(Attach.jpegName("IMG_1.heic"), "IMG_1.jpg")
        XCTAssertEqual(Attach.jpegName("noext"), "noext.jpg")
        XCTAssertEqual(Attach.body("look", ["/p/a.png", "/p/b.pdf"]), "look\n\n/p/a.png\n/p/b.pdf")
        XCTAssertEqual(Attach.body("  ", ["/p/a.png"]), "/p/a.png")
    }

    func testRunning() {
        let o: JSON = ["running": [["id": "t1", "kind": "agent", "label": "Prüfer", "since": 100, "activity": "Edit a.py"],
                                    ["id": "b7", "kind": "shell", "background": true], ["id": "x", "kind": "monitor"]],
                       "status": ["verb": "Computing", "elapsed": "4m 49s", "tokens": "↓ 7.3k tokens"]]
        let l = RunningItem.list(from: o)
        XCTAssertEqual(l.map(\.id), ["t1", "b7", "x"])
        XCTAssertEqual(l[1].label, "Aufgabe")
        XCTAssertEqual(RunningText.summary(l), "1 Agent, 1 Shell, 1 Aufgabe")
        XCTAssertEqual(l.map { RunningText.what($0) }, ["Subagent", "Hintergrund-Shell", "Monitor"])
        XCTAssertEqual(RunningText.info(LiveStatus.from(o)), "(4m 49s · ↓ 7.3k tokens)")
        XCTAssertEqual(RunningText.info(nil), "")
        XCTAssertNil(LiveStatus.from([:]))
        XCTAssertTrue(RunningItem.list(from: [:]).isEmpty)
        XCTAssertEqual(RunningText.elapsed(since: 1000, now: 1002), "jetzt")
        XCTAssertEqual(RunningText.elapsed(since: 1000, now: 1045), "45 s")
        XCTAssertEqual(RunningText.elapsed(since: 1000, now: 1200), "3 min")
        XCTAssertEqual(RunningText.elapsed(since: 1000, now: 4900), "1 h 5 min")
        XCTAssertEqual(RunningText.elapsed(since: 0, now: 1000), "")
        XCTAssertEqual(RunningText.freshPreview("Hier ist der Plan: Parser bauen", lastReply: "Hier ist der Plan: Parser bauen, dann testen"), "")
        XCTAssertEqual(RunningText.freshPreview("Hier ist der Plan", lastReply: "Etwas anderes"), "Hier ist der Plan")
    }

    func testChatHeader() {
        XCTAssertEqual(ChatHeader.shortPath("/home/martin/relay"), "~/relay")
        XCTAssertEqual(ChatHeader.shortPath("/home/martin"), "~")
        XCTAssertEqual(ChatHeader.shortPath("/tmp/x"), "/tmp/x")
        XCTAssertEqual(ChatHeader.subtitle(model: "claude-opus-5-5", effort: "low", tool: "claude", cwd: "/home/martin/relay", tokens: 120_000),
                       "opus 5.5 · low effort · Claude · ~/relay · 120k ctx")
        XCTAssertEqual(ChatHeader.subtitle(model: "", effort: "", tool: "codex", cwd: "", tokens: nil), "Codex")
    }

    func testSendWhileDictating() {
        XCTAssertTrue(DictationSend.canSend(input: "", listening: true, sending: false, hasSession: true))
        XCTAssertTrue(DictationSend.canSend(input: " hi ", listening: false, sending: false, hasSession: true))
        XCTAssertFalse(DictationSend.canSend(input: "  ", listening: false, sending: false, hasSession: true))
        XCTAssertFalse(DictationSend.canSend(input: "hi", listening: true, sending: true, hasSession: true))
        XCTAssertFalse(DictationSend.canSend(input: "hi", listening: true, sending: false, hasSession: false))
        XCTAssertEqual(DictationSend.grace, 2, accuracy: 0.001)
        XCTAssertGreaterThan(DictationSend.stuckAfter, 15)  // longer than the clean-up's own limit
    }

    func testAfterDictation() {
        XCTAssertEqual(DictationSend.afterDictation(field: " Foto dazu ", failure: nil), .send("Foto dazu"))
        XCTAssertEqual(DictationSend.afterDictation(field: "Foto", failure: "Mikro weg"), .send("Foto"))
        XCTAssertEqual(DictationSend.afterDictation(field: "  ", failure: nil), .nothing("Nichts verstanden, nichts gesendet."))
        XCTAssertEqual(DictationSend.afterDictation(field: "", failure: "Spracherkennung ist nicht verfügbar."),
                       .nothing("Nicht gesendet: Spracherkennung ist nicht verfügbar."))
    }

    func testRefusedOutboxStatus() {
        let busy = OutItem(id: "1", key: "k", text: "hi", at: 0, state: .failed, error: "session is busy")
        XCTAssertEqual(OutboxLogic.status(busy, connected: true, network: true), "Nicht gesendet: die Sitzung arbeitet gerade")
        XCTAssertTrue(OutboxLogic.isBusyRefusal(busy.error ?? ""))
        let other = OutItem(id: "2", key: "k", text: "hi", at: 0, state: .failed, error: "not sent: a Yes/No dialog is open")
        XCTAssertEqual(OutboxLogic.status(other, connected: true, network: true), "Nicht gesendet: a Yes/No dialog is open")
        // a refused message stays on disk and in the chat; only delivered ones are swept
        XCTAssertEqual(OutboxLogic.sweep([busy], seen: ["hi"], now: 1e9).count, 1)
        XCTAssertEqual(OutboxLogic.restored([busy]).first?.state, .failed)
        // "Trotzdem senden": queued with force under a fresh client_id; a queued one keeps its id
        let again = OutboxLogic.retried(busy, force: true, newId: "n")
        XCTAssertEqual(again.id, "n"); XCTAssertEqual(again.state, .queued); XCTAssertTrue(again.force); XCTAssertNil(again.error)
        XCTAssertEqual(again.text, "hi"); XCTAssertEqual(again.key, "k")
        let queued = OutItem(id: "3", key: "k", text: "x", at: 0, state: .queued, force: false)
        XCTAssertEqual(OutboxLogic.retried(queued, force: nil, newId: "n").id, "3")
        XCTAssertFalse(OutboxLogic.retried(queued, force: nil, newId: "n").force)
    }
}

final class HandoverTests: XCTestCase {
    func testPhoneIsBlockedOnlyWhileTheDeskHoldsIt() {
        XCTAssertTrue(Handover.phoneBlocked("desk"))
        XCTAssertFalse(Handover.phoneBlocked("phone"))
        XCTAssertFalse(Handover.phoneBlocked(""))
    }

    func testLabelsAndTakeButton() {
        XCTAssertEqual(Handover.label("phone"), "Am Handy")
        XCTAssertEqual(Handover.label("desk"), "Am PC")
        XCTAssertNil(Handover.label(""))
        XCTAssertEqual(Handover.takeTitle("desk"), "Sitzung übernehmen")
        XCTAssertEqual(Handover.takeTitle(""), "Sitzung übernehmen")
        XCTAssertNil(Handover.takeTitle("phone"))
    }

    func testHoldersFromSessionList() {
        let rows: JSON = [["key": "claude:c1:a", "holder": "phone"], ["key": "claude:c1:b"], ["key": "claude:c1:c", "holder": "desk"], ["holder": "desk"]]
        XCTAssertEqual(Handover.holders(in: rows), ["claude:c1:a": "phone", "claude:c1:c": "desk"])
    }
}
