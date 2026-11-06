import Foundation

/// Sitzungsübergabe zwischen Handy und PC (Gateway `handover`, PROTOCOL.md "Session handover"). Wer eine Sitzung hält,
/// steht als `holder` in `list_sessions` und `screen`: "" (offen, beide dürfen tippen), "phone" oder "desk".
/// `pc_attached` (2026-11-06) in `list_sessions`: ein Terminal am PC zeigt die Sitzung gerade (Handy-Terminals zählen nicht).
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

    /// Die Sitzungen, die ein Terminal am PC gerade zeigt (`pc_attached` in `list_sessions`).
    public static func pcAttached(in sessions: JSON) -> Set<String> {
        Set(sessions.array.filter { $0.flag("pc_attached") }.map { $0.str("key") }.filter { !$0.isEmpty })
    }

    // MARK: Nachfrage vor dem Senden (Entscheidung Martin 2026-11-05: keine automatische Übernahme)

    /// Fragt die App vor dem Senden „Sitzung vom PC übernehmen?“. Ja, wenn der PC sie ausdrücklich hält (sonst lehnt
    /// das Gateway ab) oder wenn ein PC-Terminal sie gerade zeigt und sie niemand hält; nicht, wenn das Handy sie
    /// schon hält oder Martin für diese Sitzung schon „Nur senden“ gewählt hat.
    public static func asksBeforeSend(holder: String, pcAttached: Bool, declined: Bool) -> Bool {
        if holder == phone { return false }
        if holder == desk { return true }
        return pcAttached && !declined
    }

    public static let askTitle = "Sitzung vom PC übernehmen?"

    /// Erklärung im Dialog. Hält der PC sie ausdrücklich, gibt es kein „Nur senden“.
    public static func askMessage(holder: String) -> String {
        holder == desk
            ? "Der PC hat diese Sitzung zurückgeholt. Zum Schreiben vom Handy musst du sie übernehmen; der PC wird dann schreibgeschützt (Strg-b, dann H holt sie zurück)."
            : "Diese Sitzung ist gerade in einem Terminal am PC offen. Übernehmen macht den PC schreibgeschützt (Strg-b, dann H holt sie zurück). „Nur senden“ tippt die Nachricht hinein, ohne etwas zu sperren."
    }

    public static let takeAndSend = "Übernehmen und senden"
    public static let sendOnly = "Nur senden"

    /// Ob der Dialog „Nur senden“ anbietet.
    public static func offersSendOnly(holder: String) -> Bool { holder != desk }
}
