import Foundation

/// Das Gateway kann in eine Sitzung, die am PC in einem Terminal ohne tmux läuft, nichts tippen. Die Nachricht bleibt
/// im Postausgang, das Handy liest nur mit. Mit `move` (Gateway `send {move:true}`) beendet das Gateway die Sitzung am
/// PC (SIGTERM, Claude speichert und endet) und setzt sie in tmux mit genau dieser Nachricht fort. Das geschieht nur auf
/// ausdrückliche Wahl: Knopf im Postausgang, dann Bestätigung (Martin, 2026-11-07: nie ungefragt beenden; die Rückfrage
/// erschien bis 0.3.6 von selbst nach jeder Absage).
public enum DeskTerminal {
    /// Die Absage des Gateways (`adapters/*.py send()`), an der die App den Fall erkennt.
    public static func isRefusal(_ message: String) -> Bool { message.lowercased().contains("outside tmux") }

    /// Die Sitzung lebt am PC außerhalb einer Agenten-tmux-Sitzung: ein nacktes `claude` (Codex, agy) im Terminal.
    /// `claude --bg`-Sitzungen zählen nicht (attachable: das Gateway öffnet sie bei Bedarf selbst).
    public static func isDeskTerminal(_ s: Session) -> Bool {
        s.alive && !s.exited && !s.closed && !s.background && !s.attachable && s.tmuxSession == nil && !s.placeholder
    }

    public static let statusText = "Nicht gesendet: die Sitzung ist am PC in einem Terminal ohne tmux offen"
    /// Hinweis über der Eingabe, solange die Sitzung so läuft.
    public static let hint = "Am PC in einem Terminal ohne tmux offen: vom Handy nur mitlesen. Nachrichten warten im Postausgang."
    /// Knopf im Postausgang; öffnet erst die Bestätigung.
    public static let moveButton = "Am PC beenden und hier fortsetzen…"
    public static let dialogTitle = "Die Sitzung am PC beenden und hier in tmux fortsetzen?"
    public static let dialogMessage = "Die Sitzung läuft am PC in einem Terminal ohne tmux, dort kann das Gateway nichts eintippen. Nach Ja beendet es die Sitzung am PC (Claude speichert) und setzt sie in tmux mit dieser Nachricht fort. Ohne Ja passiert am PC nichts, die Nachricht bleibt im Postausgang."
    public static let moveConfirm = "Ja, am PC beenden und hier fortsetzen"
}

/// Anzeige, ob die Sitzung gerade auch am PC offen ist (Chat-Kopf und Sitzungsliste). Nur Anzeige: keine Sperre, keine
/// Rückfrage vor dem Senden (Martin, 2026-11-07). Quelle: `pc_attached` des Gateways (ein tmux-Client am PC, ohne die
/// Terminals des Handys) in der Liste und als Ereignis; eine Sitzung in einem Terminal ohne tmux ist am PC offen,
/// solange sie lebt. Ohne Angabe (älteres Gateway, tmux antwortete nicht): unbekannt, kein Symbol.
public enum PCPresence: Equatable {
    case open, closed, unknown

    public static func of(_ s: Session) -> PCPresence {
        guard s.alive, !s.exited, !s.closed else { return .closed }
        if DeskTerminal.isDeskTerminal(s) { return .open }
        guard let a = s.pcAttached else { return .unknown }
        return a ? .open : .closed
    }

    public static let openLabel = "Am PC offen"
    public static let symbol = "desktopcomputer"

    /// Das Ereignis `pc_attached` (`session_key`, `pc_attached`) auf die Liste anwenden. true: etwas hat sich geändert.
    @discardableResult
    public static func apply(_ ev: JSON, to sessions: inout [String: Session]) -> Bool {
        let key = ev.str("session_key")
        guard var s = sessions[key], let a = ev["pc_attached"].bool, s.pcAttached != a else { return false }
        s.pcAttached = a
        sessions[key] = s
        return true
    }
}

/// Das Gateway sendet Text und Enter getrennt und prüft danach das Eingabefeld der Sitzung am PC (2026-11-07,
/// „Nachricht bleibt im Eingabefeld stehen“). Steht der Text nach zwei Enter noch da, meldet es einen Fehler. Der Text
/// ist dann am PC eingetippt, aber nicht abgeschickt: Erneutes Senden vom Handy würde ihn doppelt eintippen.
public enum SubmitCheck {
    /// Die Meldung des Gateways (`tmux.send_text`), an der die App den Fall erkennt.
    public static func isStuck(_ message: String) -> Bool { message.lowercased().contains("still in the input field") }

    public static let text = "Nicht abgeschickt: Der Text steht am PC im Eingabefeld, das Enter kam nicht an. Nicht noch einmal senden, sonst steht er doppelt da. Im Live-Bildschirm „Enter“ tippen oder am PC Enter drücken."

    /// Kurzform für Zeilen (Alle Sitzungen beenden).
    public static let short = "Text steht am PC im Eingabefeld, Enter kam nicht an"

    /// Gateway-Meldung für die Anzeige: dieser Fall auf Deutsch, alles andere unverändert.
    public static func display(_ message: String) -> String { isStuck(message) ? short : message }
}
