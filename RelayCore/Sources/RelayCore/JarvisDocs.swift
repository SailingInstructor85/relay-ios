import Foundation

/// Fotos und Dokumente an Jarvis geben (2026-11-24): über die Büroklammer im Jarvis-Chat (Mediathek mit Screenshots,
/// Kamera, Bild aus der Zwischenablage, Dateien-App) oder über „Teilen“ aus einer anderen App. Die Dateien gehen als Uploads an den PC, Jarvis bekommt die Pfade mit dem Auftrag. Jarvis hat am PC keine
/// Dateiwerkzeuge: Er kann eine Datei nicht lesen, aber mit dem Pfad an eine laufende Sitzung geben (`dispatch`) oder
/// eine neue Sitzung damit starten (`new_session`). Das sagt ihm der Auftrag, weil sein Prompt am PC liegt.
public enum JarvisDocs {
    public static let maxBytes = Attach.maxBytes

    /// Was Jarvis gefragt wird: die Pfade, Martins Auftrag (oder die Bitte um einen Vorschlag) und die Regeln.
    /// `vault`: der Vault-Ordner am PC aus den Einstellungen, Startordner für eine neue Sitzung.
    public static func prompt(message: String, paths: [String], vault: String = "") -> String {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = VaultDrop.root(vault)
        let images = paths.filter { isPicture($0) }.count
        var lines = [head(count: paths.count, images: images)]
        lines += paths.map { "- \($0)" }
        lines.append("")
        if m.isEmpty {
            lines.append("Er hat nichts dazu geschrieben. Schlage kurz vor, wohin es gehört, und frage ihn, bevor du es weitergibst.")
        } else {
            lines.append("Sein Auftrag dazu: \(m)")
        }
        lines += ["",
                  "Du kannst Dateien nicht selbst lesen. Gib sie mit dem vollen Pfad weiter: an eine laufende Sitzung, die zum Thema passt, oder an eine neue Sitzung im Ordner \(dir), die das Dokument liest und erledigt, was Martin will (zum Beispiel einsortieren). Ist nicht klar, wohin, frag kurz nach. Sag am Ende in einem Satz, wohin es gegangen ist."]
        if images > 0 {
            lines.append("Ein Bild kann die Sitzung ansehen. Gehört es zu einer Notiz im Vault (zum Beispiel der Screenshot einer Nachricht zu einer Bewerbung), legt die Sitzung es nach den Regeln des Vaults beim Vorgang ab und bindet es in die Notiz ein.")
        }
        return lines.joined(separator: "\n")
    }

    /// Was mit einer Frage an das Gateway geht (RPC `ask`). `upload`: Die Nachricht ist ein Upload (Fotos oder
    /// Dokumente mit dem Auftrag aus `prompt`). Dann steht `upload: true` dabei, und das Gateway legt dafür immer einen
    /// neuen Vorgang an, auch wenn gerade eine Rückfrage offen ist (26.11.2026: Der Auftragstext eines Uploads wurde
    /// als Antwort auf die offene Rückfrage R13 verbucht, die Rückfrage galt als beantwortet, das Dokument hatte keine
    /// eigene Kennung). Eine offene Rückfrage beantwortet nur, was Martin ohne Anhang tippt oder spricht: Dort fehlt
    /// das Feld. Ein Gateway, das das Feld nicht kennt, übergeht es.
    public static func askParams(text: String, byVoice: Bool, upload: Bool) -> [String: JSON] {
        var p: [String: JSON] = ["text": .string(text), "stream": .bool(true), "source": .string(byVoice ? "voice" : "text")]
        if upload { p["upload"] = .bool(true) }
        return p
    }

    /// Fotos und Screenshots (auch aus der Zwischenablage) sind Bilder, Videos zählen hier als Dokument.
    public static func isPicture(_ nameOrPath: String) -> Bool { Attach.isImage(nameOrPath) }

    /// Erste Zeile des Auftrags: sagt Jarvis, ob Bilder, Dokumente oder beides kommen.
    public static func head(count: Int, images: Int) -> String {
        let place = count == 1 ? "Es liegt als Upload am PC:" : "Sie liegen als Uploads am PC:"
        if images == count, count > 0 {
            return count == 1 ? "Martin gibt dir ein Bild vom iPhone (Foto oder Screenshot). \(place)"
                              : "Martin gibt dir \(count) Bilder vom iPhone (Fotos oder Screenshots). \(place)"
        }
        if images > 0 { return "Martin gibt dir \(count) Anhänge vom iPhone (Bilder und Dokumente). \(place)" }
        return count == 1 ? "Martin gibt dir ein Dokument vom iPhone. \(place)"
                          : "Martin gibt dir \(count) Dokumente vom iPhone. \(place)"
    }

    /// Name für ein Bild aus der Zwischenablage (zum Beispiel ein kopierter Screenshot).
    public static func clipboardName(stamp: Int) -> String { "zwischenablage-\(stamp).png" }

    /// Symbol einer Marke ohne Vorschaubild.
    public static func symbol(_ name: String) -> String {
        if Attach.isImage(name) { return "photo" }
        if Attach.isVideo(name) { return "video" }
        return "doc"
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
