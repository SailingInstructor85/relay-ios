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

    /// Stops the running turn (Esc, also while the session works).
    func stopTurn(_ s: Session) async throws {
        try await sendKeys(s, ["Escape"], force: true)
    }

    /// Answers the open question of a session with `params` from `AnswerKeys`.
    func answer(_ params: JSON) async throws {
        _ = try await rpc("send", params, timeout: 30)
    }
}
