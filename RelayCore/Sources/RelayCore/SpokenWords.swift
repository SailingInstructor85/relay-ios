import Foundation

/// Ausspracheliste für die Stimme Supertonic (2026-11-25, Martin nach dem ersten Hören am iPhone: „Chief“ klingt sehr
/// kurz). Supertonic liest Buchstaben ohne Aussprachewörterbuch; ein Wort, das es falsch liest, bekommt die Stimme
/// deshalb in einer Schreibweise, die sie richtig spricht. Die Apple-Stimme braucht das nicht, dort bleibt der Text.
///
/// Dieselbe Liste gehört ins Gateway (Sprachausgabe am PC), damit Jarvis an beiden Orten gleich spricht.
public enum SpokenWords {
    /// Wort → Schreibweise für die Stimme. Neue Wörter hier eintragen, eine Zeile je Wort, und in
    /// `SpokenWordsTests` einen Satz dazu. Groß- und Kleinschreibung des Wortes ist egal, ein angehängtes „s“
    /// („des Chiefs“) bleibt erhalten. Aufgenommen wird nur, was per Hörprobe geprüft ist.
    ///
    /// - „Chief“: Hörprobe am PC, 25.11.2026. Ohne Eintrag liest die Stimme den Anlaut deutsch (zurückgelesen als
    ///   „Tief“ und „Schief“), mit „Tschief“ kommt „Chief“ zurück.
    public static let german: [String: String] = [
        "Chief": "Tschief",
    ]

    /// Ersetzt jedes Wort der Liste durch seine Schreibweise für die Stimme. Nur ganze Wörter: „Chief-Sitzung“ ja,
    /// „Chiefsache“ und „Mischief“ nein.
    public static func respell(_ text: String, list: [String: String] = german) -> String {
        var t = text
        // längere Wörter zuerst, damit ein kurzer Eintrag einem langen nichts wegnimmt
        for (word, spoken) in list.sorted(by: { ($0.key.count, $0.key) > ($1.key.count, $1.key) }) where !word.isEmpty {
            let pattern = #"(?i)(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: word) + #"(s?)(?![\p{L}\p{N}])"#
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = t as NSString
            t = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: ns.length),
                                            withTemplate: NSRegularExpression.escapedTemplate(for: spoken) + "$1")
        }
        return t
    }
}
