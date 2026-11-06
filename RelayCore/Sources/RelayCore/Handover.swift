import Foundation

/// Sitzungsübergabe zwischen Handy und PC (Gateway `handover`, PROTOCOL.md "Session handover"). Wer eine Sitzung hält,
/// steht als `holder` in `list_sessions` und `screen`: "" (offen, beide dürfen tippen), "phone" oder "desk".
public enum Handover {
    public static let phone = "phone", desk = "desk"

    /// Das Gateway nimmt keinen Text vom Handy an, solange der PC die Sitzung ausdrücklich hält.
    public static func phoneBlocked(_ holder: String) -> Bool { holder == desk }

    /// Kurztext für Kopfzeile und Sitzungsliste; nil = nichts anzeigen (offen).
    public static func label(_ holder: String) -> String? {
        switch holder {
        case phone: return "Am Handy"
        case desk: return "Am PC"
        default: return nil
        }
    }

    /// Titel des Knopfs, der die Sitzung ans Handy holt; nil, wenn das Handy sie schon hält.
    public static func takeTitle(_ holder: String) -> String? { holder == phone ? nil : "Sitzung übernehmen" }

    /// Hinweis unter der Kopfzeile, wenn der PC sie hält (Eingabe gesperrt).
    public static let deskNote = "Diese Sitzung liegt am PC. Zum Schreiben hier übernehmen."

    /// Hinweis, wenn das Handy sie hält: so kommt sie am PC zurück.
    public static let phoneNote = "Das Handy hält diese Sitzung. Am PC zurückholen mit Strg-b, dann H."

    /// key -> holder aus einer `list_sessions`-Antwort (nur Sitzungen mit gesetztem Halter).
    public static func holders(in sessions: JSON) -> [String: String] {
        var out: [String: String] = [:]
        for o in sessions.array {
            let k = o.str("key"), h = o.str("holder")
            if !k.isEmpty && !h.isEmpty { out[k] = h }
        }
        return out
    }
}
