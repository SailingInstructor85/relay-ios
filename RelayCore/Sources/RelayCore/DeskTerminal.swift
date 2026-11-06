import Foundation

/// Das Gateway kann in eine Sitzung, die am PC in einem Terminal ohne tmux läuft, nichts tippen. Die Nachricht bleibt
/// im Postausgang; mit `move` (Gateway `send {move:true}`) beendet das Gateway die Sitzung am PC (SIGTERM, Claude
/// speichert und endet) und setzt sie in tmux mit genau dieser Nachricht fort. Erst nach Martins Ja (2026-11-06).
public enum DeskTerminal {
    /// Die Absage des Gateways (`adapters/*.py send()`), an der die App den Fall erkennt.
    public static func isRefusal(_ message: String) -> Bool { message.lowercased().contains("outside tmux") }

    public static let statusText = "Nicht gesendet: die Sitzung ist am PC in einem Terminal ohne tmux offen"
    public static let dialogTitle = "Die Sitzung ist am PC in einem Terminal ohne tmux offen."
    public static let dialogMessage = "Vom Handy aus lässt sich dort nichts eintippen. Soll das Gateway die Sitzung am PC beenden und hier in tmux fortsetzen? Die Nachricht wird dann dort zugestellt. Ohne dein Ja passiert am PC nichts."
    public static let moveButton = "Am PC beenden und hier fortsetzen"
}
