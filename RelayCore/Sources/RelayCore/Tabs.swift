import Foundation

/// Die fünf Tabs der Startseite, in der Reihenfolge der Leiste.
public enum AppTab: String, CaseIterable, Sendable, Hashable {
    case today, yourTurn, sessions, inbox, more

    /// Beschriftung in der Tab-Leiste.
    public var title: String {
        switch self {
        case .today: return "Heute"
        case .yourTurn: return "Dein Zug"
        case .sessions: return "Sitzungen"
        case .inbox: return "Posteingang"
        case .more: return "Mehr"
        }
    }

    /// SF Symbol des Tabs.
    public var symbol: String {
        switch self {
        case .today: return "house.fill"
        case .yourTurn: return "checkmark.circle.fill"
        case .sessions: return "person.fill"
        case .inbox: return "envelope.fill"
        case .more: return "ellipsis"
        }
    }
}

/// Ein Ziel, das in den Stapel eines Tabs geschoben wird (Unterseite).
public enum Route: Hashable, Sendable {
    case chat(String)
    /// Chat mit vorbelegter Suche im Verlauf (Sitzungsschlüssel, Suchtext).
    case chatSearch(String, String)
    case settings, usage, memory, digest, tokens
    case jarvis, jarvisListening
    /// Jarvis öffnen und diese Frage sofort stellen (Eingabeleiste auf „Heute“).
    case jarvisAsk(String)
    /// Jarvis öffnen und `text` sofort senden; im Verlauf steht dafür `shown` (Dokumente aus dem Teilen-Blatt: der
    /// Auftrag mit den Pfaden geht an Jarvis, zu sehen sind Nachricht und Dateinamen).
    case jarvisSend(shown: String, text: String)
    case notices
    case notice(String)
    case routines, drive, vaultChat
    /// Smart Home: fest hinterlegte Aktionen, die das Gateway am PC ausführt (Fernseher).
    case smartHome
    /// Eine Mail aus dem Posteingang (Nummer im Index des Gateways), nur lesen.
    case mail(String)
    /// Wochenliste des Kalenders (Tipp auf die Kalenderkarte auf „Heute“).
    case calendar

    /// Unterseiten mit eigener Eingabeleiste oder Sprachbedienung: dort verschwindet die Tab-Leiste.
    public var hidesTabBar: Bool {
        switch self {
        case .chat, .chatSearch, .jarvis, .jarvisListening, .jarvisAsk, .jarvisSend, .drive, .vaultChat: return true
        default: return false
        }
    }
}

/// Ein Sprung von außen: Tipp auf eine Mitteilung, Siri-Kurzbefehl.
public enum Jump: Equatable, Sendable {
    /// Sitzungsschlüssel (oder der Schlüssel des Vault-Chats).
    case chat(String)
    /// Hinweis; `openQuestion`: eine Rückfrage, die noch auf Antwort wartet.
    case notice(ref: String, openQuestion: Bool)
    /// Jarvis per Sprache.
    case jarvis
    /// Sprachmodus für offene Rückfragen.
    case drive
}

public enum TabRouting {
    /// In welchem Tab ein Sprung landet und welcher Stapel dort danach liegt (der alte Stapel des Tabs wird ersetzt).
    /// Chats gehören zu „Sitzungen“, offene Rückfragen und der Sprachmodus zu „Dein Zug“, übrige Hinweise zu „Mehr“
    /// (dort liegt die Liste der Hinweise, Zurück führt zu ihr), Jarvis zu „Heute“ (dort steht die Assistent-Karte).
    public static func target(_ jump: Jump) -> (tab: AppTab, path: [Route]) {
        switch jump {
        case .chat(let key):
            return (.sessions, [VaultChat.isVault(key) ? .vaultChat : .chat(key)])
        case .notice(let ref, let open):
            return open ? (.yourTurn, [.notice(ref)]) : (.more, [.notices, .notice(ref)])
        case .jarvis:
            return (.today, [.jarvisListening])
        case .drive:
            return (.yourTurn, [.drive])
        }
    }

    /// Text des Abzeichens am Tab: nichts bei 0, ab 100 „99+“.
    public static func badge(_ count: Int) -> String? {
        if count <= 0 { return nil }
        return count > 99 ? "99+" : String(count)
    }
}
