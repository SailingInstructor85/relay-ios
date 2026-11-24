import Foundation

/// Dokumente an Jarvis geben (2026-11-24): über die Büroklammer im Jarvis-Chat oder über „Teilen“ aus einer anderen
/// App. Die Dateien gehen als Uploads an den PC, Jarvis bekommt die Pfade mit dem Auftrag. Jarvis hat am PC keine
/// Dateiwerkzeuge: Er kann eine Datei nicht lesen, aber mit dem Pfad an eine laufende Sitzung geben (`dispatch`) oder
/// eine neue Sitzung damit starten (`new_session`). Das sagt ihm der Auftrag, weil sein Prompt am PC liegt.
public enum JarvisDocs {
    public static let maxBytes = Attach.maxBytes

    /// Was Jarvis gefragt wird: die Pfade, Martins Auftrag (oder die Bitte um einen Vorschlag) und die Regeln.
    /// `vault`: der Vault-Ordner am PC aus den Einstellungen, Startordner für eine neue Sitzung.
    public static func prompt(message: String, paths: [String], vault: String = "") -> String {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = VaultDrop.root(vault)
        var lines = [paths.count == 1 ? "Martin gibt dir ein Dokument vom iPhone. Es liegt als Upload am PC:"
                                      : "Martin gibt dir \(paths.count) Dokumente vom iPhone. Sie liegen als Uploads am PC:"]
        lines += paths.map { "- \($0)" }
        lines.append("")
        if m.isEmpty {
            lines.append("Er hat nichts dazu geschrieben. Schlage kurz vor, wohin es gehört, und frage ihn, bevor du es weitergibst.")
        } else {
            lines.append("Sein Auftrag dazu: \(m)")
        }
        lines += ["",
                  "Du kannst Dateien nicht selbst lesen. Gib sie mit dem vollen Pfad weiter: an eine laufende Sitzung, die zum Thema passt, oder an eine neue Sitzung im Ordner \(dir), die das Dokument liest und erledigt, was Martin will (zum Beispiel einsortieren). Ist nicht klar, wohin, frag kurz nach. Sag am Ende in einem Satz, wohin es gegangen ist."]
        return lines.joined(separator: "\n")
    }

    /// Was im Jarvis-Chat als eigene Nachricht steht: der Text und darunter die Dateinamen, nicht der ganze Auftrag.
    public static func shown(message: String, names: [String]) -> String {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = names.isEmpty ? "" : (names.count == 1 ? "Anhang: " : "Anhänge: ") + names.joined(separator: ", ")
        if m.isEmpty { return files }
        return files.isEmpty ? m : "\(m)\n\(files)"
    }

    /// Senden geht auch ohne Text, sobald ein Dokument angehängt ist.
    public static func canSend(docs: Int, asking: Bool) -> Bool { docs > 0 && !asking }

    public static func progress(index: Int, count: Int, name: String) -> String {
        count > 1 ? "Lade \(index + 1)/\(count) \(name) hoch…" : "Lade \(name) hoch…"
    }

    public static func tooBig(_ name: String) -> String { "\(name) ist größer als 50 MB" }
    public static func unreadable(_ name: String) -> String { "\(name) konnte nicht gelesen werden" }
}
