import Foundation

/// Smart Home im Tab „Mehr“: Die App schaltet nichts selbst. Sie bittet das Gateway am PC um eine von wenigen fest
/// hinterlegten Aktionen (rpc `smart_home`), das Gateway startet dafür sein eigenes, geprüftes Skript und meldet
/// dessen Ausgabe zurück. Freie Befehle vom Handy gibt es nicht: Die App schickt nur Gerät und Aktionsnamen.
public enum SmartHome {
    public static let rpc = "smart_home"
    /// Ein kalter Fernseher braucht bis zu drei Minuten, bis er antwortet.
    public static let timeout: Double = 200

    public struct Action: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let symbol: String
        /// Zeile, solange die Aktion läuft.
        public let running: String
    }

    public static let tvDevice = "tv"

    /// Die Aktionen des Fernsehers in der Reihenfolge der Anzeige.
    public static let tv: [Action] = [
        Action(id: "on", title: "Fernseher einschalten", symbol: "power", running: "Fernseher wird eingeschaltet …"),
        Action(id: "hdmi2", title: "HDMI 2 aktivieren", symbol: "cable.connector", running: "Schalte auf HDMI 2 …"),
        Action(id: "tv", title: "Fernsehen", symbol: "tv", running: "Schalte auf Fernsehen …"),
        Action(id: "off", title: "Fernseher ausschalten", symbol: "moon", running: "Fernseher wird ausgeschaltet …"),
    ]

    public static let slowNote = "Das kann bis zu 3 Minuten dauern, wenn der Fernseher kalt startet."

    /// Parameter des Aufrufs: nur Gerät und Aktionsname.
    public static func params(_ action: Action, device: String = tvDevice) -> JSON {
        ["device": .string(device), "action": .string(action.id)]
    }

    public struct Outcome: Sendable, Equatable {
        public let ok: Bool
        public let text: String
        public init(ok: Bool, text: String) { self.ok = ok; self.text = text }
    }

    /// Antwort des Gateways `{ok, text}`: `text` ist die Rückmeldung des Skripts („Umgeschaltet auf HDMI 2“).
    public static func outcome(_ reply: JSON, action: Action) -> Outcome {
        let ok = reply.flag("ok", true)
        let text = clean(reply.str("text"))
        if !text.isEmpty { return Outcome(ok: ok, text: text) }
        return Outcome(ok: ok, text: ok ? "Erledigt: \(action.title)." : "Das hat nicht geklappt, das Gateway nennt keinen Grund.")
    }

    /// Der Aufruf ist gescheitert. `remote`: Das Gateway hat geantwortet und abgelehnt, sonst ist die Verbindung das Problem.
    public static func failure(message: String, remote: Bool) -> Outcome {
        if remote && InboxText.isUnknownRpc(message) {
            return Outcome(ok: false, text: "Das Gateway auf dem PC kann den Fernseher noch nicht schalten. Der Befehl kommt mit einer neueren Fassung des Gateways.")
        }
        if remote { return Outcome(ok: false, text: "Das Gateway meldet: \(clean(message))") }
        return Outcome(ok: false, text: "Keine Antwort vom PC: \(clean(message))")
    }

    /// Die letzten Zeilen einer Skriptausgabe, ohne Leerzeilen, höchstens 400 Zeichen.
    static func clean(_ raw: String) -> String {
        let lines = raw.replacingOccurrences(of: "\r", with: "\n").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let text = lines.suffix(4).joined(separator: "\n")
        return text.count > 400 ? String(text.prefix(400)) + " …" : text
    }
}
