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
        if background && state != .connected { _ = await connectOnce() }
        guard state == .connected else { return "Nicht verbunden: die Antwort konnte nicht zum PC." }
        let item = Rueckfrage.answerItem(agent: q.agent, id: q.id, answer: t, now: Date().timeIntervalSince1970)
        do { _ = try await rpc("inbox_put", ["kind": .string("notification"), "items": .array([item])], timeout: 30) }
        catch { return "Antwort nicht angekommen: \(error.localizedDescription)" }
        NoticeStore.shared.setAnswer(ref: ref, t)
        Notifier.remove([NoticeLogic.slot(tag: n.tag, seq: 0)])
        return nil
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
