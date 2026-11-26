import Foundation

/// Nachrichten an Jarvis ohne Verbindung (Martin, 26.11.2026: „was eingesprochen … war offline und dann hat er sich das
/// nicht gespeichert“). Was im Jarvis-Feld oder in der Eingabeleiste auf „Heute“ getippt oder eingesprochen wird,
/// während der PC nicht erreichbar ist, wartet in derselben Outbox wie die Sitzungs- und Vault-Chats, unter dem
/// Zielschlüssel `key`. Sobald die Verbindung steht, geht es der Reihe nach an `ask`, auch nach einem Neustart der App.
/// Die Kennung der Nachricht geht als `client_id` mit.
///
/// Nichts doppelt: Ein Gateway, das `client_id` bei `ask` auswertet, meldet das mit `ask_once` in `hello_ok.config`
/// (`once`). Dann darf eine Frage, deren Antwort verloren ging, von selbst noch einmal hinaus. Ohne diese Zusage
/// sendet die App nur dann von selbst erneut, wenn die Frage sicher nicht am PC angekommen ist. Riss die Verbindung
/// beim Warten auf die Antwort, bleibt die Nachricht mit „Erneut senden“ stehen, statt den Auftrag ungefragt ein
/// zweites Mal auszulösen.
public enum JarvisOutbox {
    /// Zielschlüssel in der Outbox (es gibt keine Sitzung dazu).
    public static let key = "jarvis:ask"

    public static func isJarvis(_ key: String) -> Bool { key == Self.key }

    /// Abstand zwischen zwei Fragen aus der Warteschlange, damit sie in der Reihenfolge des Eingangs am PC ankommen.
    /// Sie warten nicht aufeinander: Eine Antwort kann Minuten dauern.
    public static let startGap: Double = 3

    public static let unclearText = "Die Verbindung riss ab, bevor die Antwort kam. Ob die Nachricht am PC angekommen ist, ist offen."
    public static let lostFiles = "Der Anhang ist auf dem iPhone nicht mehr vorhanden."
    /// Was Jarvis sagt, wenn eine eingesprochene Frage erst einmal wartet.
    public static let spokenQueued = "Keine Verbindung. Ich sende es, sobald sie wieder steht."
    public static let menuTitle = "Nachricht an Jarvis"
    public static let sendNow = "Jetzt senden", sendAgain = "Erneut senden", edit = "Bearbeiten", delete = "Löschen"

    /// Die nächste Nachricht für den Sender der Outbox: die älteste wartende, die jetzt hinaus darf. Nachrichten an
    /// Jarvis gehen im Hintergrund nur mit `once` (iOS hält die App an, bevor die Antwort da ist) und nie dichter als
    /// `startGap` hintereinander. Alles andere wie bisher der Reihe nach.
    public static func next(_ items: [OutItem], foreground: Bool, once: Bool, now: Double, lastStart: Double) -> OutItem? {
        let jarvisOk = (foreground || once) && now - lastStart >= startGap
        return items.first { $0.state == .queued && (!isJarvis($0.key) || jarvisOk) }
    }

    /// Ein früherer Versuch dieser Nachricht ging hinaus, sein Ausgang ist unbekannt (die App wurde dabei beendet).
    /// Ohne `once` geht sie nicht von selbst noch einmal.
    public static func unclear(_ i: OutItem, once: Bool) -> Bool { i.tries > 0 && !once }

    /// Der Fehlertext von `AppModel.rpc`, wenn gar keine Verbindung bestand: Dann ging nichts hinaus.
    public static func notSent(_ message: String) -> Bool { message.hasPrefix("Nicht verbunden") }

    public enum Outcome: Equatable {
        /// wartet weiter und geht von selbst noch einmal hinaus; `sent`: Der Versuch hat den PC vielleicht erreicht
        case again(sent: Bool)
        /// Ausgang offen: bleibt stehen, der Nutzer entscheidet
        case unclear
        /// das Gateway hat abgelehnt
        case refused(String)
    }

    /// Was nach einem gescheiterten `ask` geschieht. `remote`: Das Gateway hat geantwortet und abgelehnt.
    public static func outcome(remote: Bool, message: String, once: Bool) -> Outcome {
        if remote { return .refused(message) }
        if notSent(message) { return .again(sent: false) }
        return once ? .again(sent: true) : .unclear
    }

    /// Die Nachricht nach einem gescheiterten Versuch (`outcome`).
    public static func failed(_ i: OutItem, _ o: Outcome, message: String) -> OutItem {
        var c = i
        switch o {
        case .again(let sent):
            c.state = .queued; c.error = message
            if !sent { c.tries = max(0, c.tries - 1) }
        case .unclear:
            c.state = .failed; c.error = unclearText
        case .refused(let why):
            c.state = .failed; c.error = why
        }
        return c
    }

    /// Was im Verlauf steht: der Text und darunter die Namen der Anhänge.
    public static func shownText(_ i: OutItem) -> String {
        if let s = i.shown, !s.isEmpty { return s }
        return JarvisDocs.shown(message: i.text, names: i.files.map(VaultChat.displayName))
    }

    /// Die Anhänge sind am PC: Aus der Nachricht wird der Auftrag mit den Pfaden. Die Dateien auf dem iPhone braucht
    /// es danach nicht mehr, ein weiterer Versuch lädt nichts doppelt hoch.
    public static func uploaded(_ i: OutItem, paths: [String], vault: String) -> OutItem {
        guard !paths.isEmpty else {
            var c = i; c.files = []; return c
        }
        return OutItem(id: i.id, key: i.key, text: JarvisDocs.prompt(message: i.text, paths: paths, vault: vault), at: i.at,
                       state: i.state, error: i.error, tries: i.tries, doneAt: i.doneAt, force: i.force, files: [],
                       voice: i.voice, shown: shownText(i), upload: true)
    }

    /// Was an `ask` geht. Ohne Streaming: Die Antwort kommt am Stück in die Zeile.
    public static func params(_ i: OutItem) -> [String: JSON] {
        var p = JarvisDocs.askParams(text: i.text, byVoice: i.voice, upload: i.upload)
        p["stream"] = .bool(false)
        p["client_id"] = .string(i.id)
        return p
    }

    /// Kennung der Antwort im gespeicherten Verlauf: Daran fällt auf, wenn dieselbe Antwort zweimal eintrifft.
    public static func ref(_ id: String) -> String { "ask:" + id }

    /// Der Zug für den Verlauf, sobald die Antwort da ist.
    public static func turn(_ i: OutItem, answer: String, now: Double) -> JarvisTurn {
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return JarvisTurn(id: UUID(uuidString: i.id) ?? UUID(), q: shownText(i), a: a.isEmpty ? "Jarvis hat nichts geantwortet." : a,
                          voice: i.voice, ts: now, ref: ref(i.id))
    }

    /// Wird ein Zug vorgelesen, der nachträglich in den Verlauf kommt? Rückmeldungen des Chiefs (mit Thema) wie
    /// bisher immer. Antworten auf Fragen aus der Warteschlange nur, wenn die Frage eingesprochen war und die App im
    /// Vordergrund ist.
    public static func speaks(_ t: JarvisTurn, foreground: Bool) -> Bool {
        t.topic != nil || (t.voice && foreground)
    }

    /// Bearbeiten geht, solange der Text noch der getippte ist (nicht der Auftrag mit den Pfaden der Uploads).
    public static func editable(_ i: OutItem) -> Bool { i.state != .sending && !i.upload && i.shown == nil }

    /// Antippen bietet etwas an, solange die Nachricht nicht gerade unterwegs ist.
    public static func actionable(_ i: OutItem) -> Bool { i.state == .queued || i.state == .failed }

    /// Die Zeile unter einer wartenden Nachricht. `taken`: „Chief hat es“, sobald das Gateway das meldet.
    public static func status(_ i: OutItem, connected: Bool, network: Bool, taken: String? = nil) -> String {
        switch i.state {
        case .delivered: return "gesendet"
        case .sending: return taken ?? "sendet…"
        case .queued:
            if connected { return "sendet gleich…" }
            return network ? "wartet auf Verbindung" : "wartet auf Netz"
        case .failed:
            let e = (i.error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return e == unclearText ? e : "Nicht gesendet: " + (e.isEmpty ? "abgelehnt" : e)
        }
    }

    /// Mitteilung, wenn die Antwort eintrifft, während der Jarvis-Chat nicht zu sehen ist.
    public static func noticeTitle(_ i: OutItem) -> String { "Jarvis: " + String(shownText(i).prefix(60)) }
}
