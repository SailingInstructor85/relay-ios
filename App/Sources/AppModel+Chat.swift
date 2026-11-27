import Foundation
import RelayCore

/// What writing in a chat needs from the model: a liveness check before input, the summary, dictation clean-up.
extension AppModel {
    /// A link that was quiet for 20 s may be dead (sleeping desktop, changed network). Before input: `ping` (6 s); no
    /// answer drops the link and waits for the new one (up to 15 s). False when there is no link in the end.
    func ensureAlive() async -> Bool {
        guard state == .connected else { return false }
        if Date().timeIntervalSince(lastTraffic) < 20 { return true }
        if (try? await rpc("ping", timeout: 6)) != nil { return true }
        let t0 = Date()
        reconnect()
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if state == .connected && lastTraffic > t0 { return true }
        }
        return false
    }

    /// The "Weiter" action of a "ready" notification: the first quick reply goes to the session.
    func quickFromNotification(key: String) async {
        guard let text = ChatPrefs.quickReplies.first else { return }
        await replyFromNotification(key: key, text: text)
    }

    /// 1 to 3 sentences about the session (rpc `speak_summary`; costs Haiku tokens on the pool account).
    func summarize(_ s: Session, lang: String = "auto") async throws -> String {
        let r = try await rpc("speak_summary", ["key": .string(s.key), "name": .string(s.name), "lang": .string(lang)], timeout: 90)
        let t = r.str("text").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw RelayError("Die Zusammenfassung ist leer.") }
        return t
    }

    /// At the start of a dictation: readies the cleaning model on the Desktop while the user talks.
    func cleanWarm() {
        Task { _ = try? await rpc("clean_warm", [:], timeout: 10) }
    }

    /// The dictation cleaned up on the Desktop (fixes misheard words with the session as context, drops fillers); nil when
    /// it can't or is slow: the raw text stays.
    func cleanDictation(_ said: String, before: String, session: String) async -> String? {
        guard state == .connected else { return nil }
        let p: JSON = ["text": .string(said), "before": .string(before), "session_key": .string(session)]
        guard let r = try? await rpc("clean_dictation", p, timeout: 15), r.flag("cleaned") else { return nil }
        let t = r.str("text").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// The gateway's vocabulary and corrections for the speech recogniser.
    func loadVocab(into voice: VoiceIO) async {
        guard let r = try? await rpc("voice_vocab", timeout: 10) else { return }
        voice.terms = r["terms"].array.compactMap(\.string)
        voice.corrections = r["corrections"].array.compactMap { (pair: JSON) -> (heard: String, meant: String)? in
            let a = pair.array
            guard a.count == 2, let h = a[0].string, let m = a[1].string else { return nil }
            return (h, m)
        }
    }

    /// The account for a session started without asking: the last chosen one if still there, else the first logged-in
    /// Claude account, else "auto".
    var defaultLaunchAlias: String {
        if !lastAlias.isEmpty, lastAlias == "auto" || accounts.contains(where: { $0.alias == lastAlias }) { return lastAlias }
        return accounts.first { $0.tool == "claude" && $0.loggedIn }?.alias ?? accounts.first?.alias ?? "auto"
    }

    /// Opens the chat of a session just launched (`launch` returns the tmux session; the session itself follows shortly).
    func openLaunched(tmux target: String) async {
        for _ in 0..<20 {
            if let s = session(for: "tmux:\(target)") { openChat = s.key; return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
        }
    }

    /// Stops the running turn (Esc, also while the session works).
    func stopTurn(_ s: Session) async throws {
        try await sendKeys(s, ["Escape"], force: true)
    }

    /// Answers the open question of a session with `params` from `AnswerKeys`.
    func answer(_ params: JSON) async throws {
        _ = try await rpc("send", params, timeout: 30)
    }

    /// The answer to an agent's question (a notice with tag `rueckfrage:<agent>:R<n>`): one inbox item (`inbox_put`,
    /// kind notification, app rueckfrage) that `rueckfrage warten` on the Desktop picks up. From a notification
    /// (`background`) a short link of its own is opened first; in the foreground the main loop keeps the link. Returns
    /// nil once the Desktop has it, else what went wrong (the answer is then still in the field).
    func answerQuestion(ref: String, text: String, background: Bool = false) async -> String? {
        guard let n = NoticeStore.shared.get(ref), let q = Rueckfrage.question(n), q.wantsAnswer else {
            return "Diese Rückfrage ist nicht mehr auf dem iPhone."
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "Die Antwort ist leer." }
        // schon woanders beantwortet (Ereignis rueckfrage_resolved oder Abgleich): nichts mehr schicken
        if let a = n.answer { return Rueckfrage.alreadyAnswered(a) }
        if background && state != .connected { _ = await connectOnce() }
        guard state == .connected else { return "Nicht verbunden: die Antwort konnte nicht zum PC." }
        let item = Rueckfrage.answerItem(agent: q.agent, id: q.id, answer: t, now: Date().timeIntervalSince1970)
        var failure: String?
        do { _ = try await rpc("inbox_put", ["kind": .string("notification"), "items": .array([item])], timeout: 30) }
        catch { failure = "Antwort nicht angekommen: \(error.localizedDescription)" }
        // Die Schließung kam, während die Antwort unterwegs war: Es gilt, was am PC steht. Die eigene Antwort kommt
        // als rueckfrage_resolved zurück und ist dann kein Widerspruch.
        if let a = NoticeStore.shared.get(ref)?.answer {
            if a == t { DraftStore.shared.remove(Drafts.question(ref)) }
            return a == t ? nil : Rueckfrage.alreadyAnswered(a)
        }
        if let failure { return failure }
        // beantwortet: Der Entwurf dieser Rückfrage ist erledigt (auch wenn „Ja (Empfehlung)“ statt des Felds galt)
        DraftStore.shared.remove(Drafts.question(ref))
        NoticeStore.shared.setAnswer(ref: ref, t)
        Notifier.remove([NoticeLogic.slot(tag: n.tag, seq: 0)])
        return nil
    }

    /// Nach jedem `hello_ok`: die noch offenen Rückfragen mit dem Stand am PC abgleichen (RPC `rueckfrage_status`).
    /// Was dort beantwortet ist oder nicht mehr existiert, geht hier zu. Kennt das Gateway den RPC nicht oder
    /// scheitert er, bleibt alles offen.
    func reconcileQuestions() async {
        let tags = Rueckfrage.openTags(NoticeStore.shared.items)
        guard !tags.isEmpty else { return }
        guard let r = try? await rpc("rueckfrage_status", ["tags": .array(tags.map { .string($0) })], timeout: 20) else { return }
        NoticeStore.shared.reconcile(status: r)
    }

    /// Beim Öffnen der App (nach `hello_ok` und dem Abgleich, oder zurück im Vordergrund bei stehender Verbindung):
    /// Sind Rückfragen offen und ist seit dem letzten „Später“ eine neue dazugekommen, geht das Blatt mit der ältesten
    /// auf. Nie mitten in der Nutzung, nie über der Sperre (dann nach dem Entsperren) und nicht, wenn die App über
    /// eine Mitteilung geöffnet wurde, die schon zu einem Hinweis führt. Ohne Verbindung bleibt es zu: der Abgleich
    /// fehlt dann, und eine Antwort käme nicht an.
    func offerQuestionPrompt() {
        guard questionPromptDue, isForeground, configured, state == .connected, !locked else { return }
        questionPromptDue = false
        guard !showQuestionPrompt, openNotice == nil, incomingFiles.isEmpty, !Approvals.shared.showSheet else { return }
        let later = UserDefaults.standard.double(forKey: QuestionPrompt.laterKey)
        guard QuestionPrompt.offer(NoticeStore.shared.items, laterUpTo: later) != nil else { return }
        UsageRecorder.shared.record("rückfrageblatt", "geöffnet")
        showQuestionPrompt = true
    }

    /// „Später“ (auch Herunterwischen): Das Blatt bleibt zu, bis eine neuere Rückfrage kommt.
    func questionPromptLater() {
        let d = UserDefaults.standard
        d.set(QuestionPrompt.later(NoticeStore.shared.items, previous: d.double(forKey: QuestionPrompt.laterKey)), forKey: QuestionPrompt.laterKey)
        if showQuestionPrompt { UsageRecorder.shared.record("rückfrageblatt", "später") }
        showQuestionPrompt = false
    }

    /// "Antworten" or "Ja" on the question's notification (the background link is closed again afterwards). A failure
    /// comes back as a notification, so the answer is never lost in silence.
    func answerFromNotification(ref: String, text: String) async {
        if let why = await answerQuestion(ref: ref, text: text, background: true) {
            Notifier.post(id: "rueckfrage-fail-\(ref)", title: "Antwort nicht angekommen", body: "\(why) Antwort: \(text)",
                          userInfo: ["notice": ref])
        }
        releaseBackground()
    }
}
