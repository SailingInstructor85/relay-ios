import Foundation

/// Der offene Chat nach einer neuen Verbindung (2026-11-12, „Antwort des Agenten kommt in der App nicht an“): Das
/// Mitlesen (`watch`) gilt im Gateway je Verbindung. Bricht sie ab, während die App im Hintergrund ist, und antwortet
/// der Agent in dieser Zeit, fehlte die Antwort im offenen Chat, bis er geschlossen und neu geöffnet wurde. Nach jedem
/// `hello_ok` lädt der Chat deshalb die neueste Seite des Verlaufs nach und meldet das Mitlesen neu an.
public enum TranscriptSync {
    public struct Result: Equatable, Sendable {
        public let messages: [TMessage]
        /// Wie viele Nachrichten der Chat vorher nicht kannte.
        public let added: Int
        /// Die Liste beginnt jetzt mit der nachgeladenen Seite: deren `before` gilt für „Ältere Nachrichten laden“.
        public let replaced: Bool
    }

    /// `old`: was der Chat zeigt. `latest`: die neueste Seite des Verlaufs (`transcript {limit}`), älteste zuerst.
    /// Bekannte Nachrichten werden durch den neuen Stand ersetzt (eine Antwort kann gewachsen sein), unbekannte kommen
    /// dazu, früher geladene ältere Seiten bleiben. Überschneidet sich nichts (es kam mehr als eine Seite dazu), gilt
    /// die neue Seite allein, damit keine Lücke im Verlauf steht.
    public static func merge(_ old: [TMessage], latest: [TMessage]) -> Result {
        guard !latest.isEmpty else { return Result(messages: old, added: 0, replaced: false) }
        let known = Set(old.map(\.id))
        let fresh = Set(latest.map(\.id))
        let added = latest.filter { !known.contains($0.id) }.count
        guard let cut = old.firstIndex(where: { fresh.contains($0.id) }) else {
            return Result(messages: latest, added: added, replaced: true)
        }
        let head = Array(old[..<cut])
        return Result(messages: head + latest, added: added, replaced: head.isEmpty && !known.contains(latest[0].id))
    }
}

/// Die App geht in den Hintergrund, während eine Sitzung arbeitet: Sie bittet iOS um die übliche Nachlaufzeit (rund
/// 30 Sekunden) und hält die Verbindung so lange, damit eine kurze Antwort noch ihre Mitteilung „Fertig“ auslöst.
/// Danach trennt iOS die Verbindung wie bisher; was später kommt, zeigt der Chat nach dem Wiederverbinden
/// (`TranscriptSync`) und die Sammelmitteilung der verpassten Ereignisse.
public enum BackgroundLinger {
    /// Sekunden, die die Verbindung im Hintergrund höchstens gehalten wird (unter der Nachlaufzeit von iOS).
    public static let maxSeconds: Double = 25

    /// Lohnt das Halten: arbeitet gerade eine Sitzung, die kein Hintergrundlauf ist?
    public static func wanted(_ sessions: [Session]) -> Bool {
        sessions.contains { $0.alive && !$0.exited && !$0.closed && !$0.background && $0.state == "busy" }
    }

    /// Ende des Haltens: wieder im Vordergrund, Zeit um, Verbindung weg oder nichts arbeitet mehr.
    public static func done(_ sessions: [Session], elapsed: Double, foreground: Bool, connected: Bool) -> Bool {
        foreground || !connected || elapsed >= maxSeconds || !wanted(sessions)
    }
}
