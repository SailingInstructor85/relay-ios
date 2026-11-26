import Foundation

/// Eine Zeile `rpc_progress` des Gateways: ein Textstück der gestreamten Antwort (`delta`) oder eine Statuszeile
/// (`status`). Statuszeilen schickt das Gateway nur, wenn die Anfrage sie mit `status: true` verlangt.
public enum RpcProgress: Equatable, Sendable {
    case delta(String)
    case status(String)

    public static func kind(_ o: JSON) -> RpcProgress {
        let s = o.str("status")
        return s.isEmpty ? .delta(o.str("delta")) : .status(s)
    }
}

/// Das Jarvis-Feld parallel (Martin, 25.11.2026: „ich will jetzt nicht einen Vorschlag machen und dann ne Minute
/// warten“): Eine Frage sperrt das Feld nicht mehr. Sobald der Chief die Nachricht hat, steht das unter der Frage.
public enum JarvisAsk {
    /// Was unter der Frage steht, sobald das Gateway meldet, dass die Nachricht angekommen ist (`status: taken`, mit
    /// dem Namen dessen, der sie hat). nil bei jeder anderen Statuszeile.
    public static func statusLabel(_ o: JSON) -> String? {
        guard o.str("status") == "taken" else { return nil }
        let name = o.str("name").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name.isEmpty ? "Jarvis" : name) hat es"
    }

    /// Wie viele Antworten noch ausstehen, als Hinweis über dem Feld; nil bei höchstens einer (die zeigt ihr eigener
    /// Fortschrittskreis).
    public static func pendingLabel(_ n: Int) -> String? {
        n > 1 ? "\(n) Antworten stehen noch aus. Du kannst weiterschreiben." : nil
    }
}

/// Ein Ergebnis, das der Chief später von sich aus in den Jarvis-Chat schreibt (Werkzeug `jarvis_say(topic, text)` am
/// PC). Es kommt als Hinweis (`notice`) mit `kind: jarvis_say`: Ältere Apps zeigen ihn als gewöhnlichen Hinweis, hier
/// steht er zusätzlich mit dem Thema als Überschrift im Chat und wird vorgelesen.
public enum JarvisSay {
    public static let kind = "jarvis_say"
    /// Überschrift, wenn das Thema fehlt.
    public static let noTopic = "Rückmeldung"

    public static func isSay(_ ev: JSON) -> Bool { ev.str("kind") == kind }

    /// Der Eintrag für den Verlauf aus dem Ereignis; nil, wenn es keine Rückmeldung für den Chat ist oder der Text fehlt.
    /// `ref` ist der `tag` des Hinweises (je Rückmeldung eindeutig), ersatzweise seine Folgenummer: Daran fallen
    /// Dubletten auf, wenn das Gateway nach einer Verbindungspause Ereignisse wiederholt.
    public static func turn(from ev: JSON, now: Double) -> JarvisTurn? {
        guard isSay(ev) else { return nil }
        let text = ev.str("text").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let topic = ev.str("title").trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = ev.str("tag")
        let seq = ev["seq"].int ?? 0
        let ref = !tag.isEmpty ? tag : seq > 0 ? "s\(seq)" : "l\(Int(now * 1000))"
        let ts = ev.num("ts")
        return JarvisTurn(q: "", a: text, voice: false, ts: ts > 0 ? ts : now, topic: topic.isEmpty ? noTopic : topic, ref: ref)
    }

    /// Der gespeicherte Verlauf mit der neuen Rückmeldung am Ende; nil, wenn sie schon darin steht.
    public static func adding(_ say: JarvisTurn, to stored: [JarvisTurn]) -> [JarvisTurn]? {
        guard let ref = say.ref, !stored.contains(where: { $0.ref == ref }) else { return nil }
        return stored + [say]
    }

    /// Rückmeldungen aus dem Speicher, die in der Ansicht noch fehlen (in der Reihenfolge des Speichers).
    public static func missing(in turns: [JarvisTurn], stored: [JarvisTurn]) -> [JarvisTurn] {
        let known = Set(turns.compactMap(\.ref))
        return stored.filter { t in t.ref.map { !known.contains($0) } ?? false }
    }

    /// Was gespeichert wird: der Verlauf der Ansicht und dahinter Rückmeldungen, die inzwischen im Speicher gelandet
    /// sind. So überschreibt eine eben fertige Antwort keine Rückmeldung, die währenddessen eintraf.
    public static func merge(_ turns: [JarvisTurn], stored: [JarvisTurn]) -> [JarvisTurn] {
        turns + missing(in: turns, stored: stored)
    }

    /// Was die Stimme liest: erst das Thema, dann das Ergebnis.
    public static func spoken(_ t: JarvisTurn) -> String {
        let topic = (t.topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return t.a }
        let end = topic.last.map { ".!?:".contains($0) } ?? false
        return topic + (end ? " " : ". ") + t.a
    }
}
