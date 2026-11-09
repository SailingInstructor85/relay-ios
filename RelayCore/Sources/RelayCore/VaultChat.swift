import Foundation

/// Chat for the agent in the vault that also works without a link (Martin, 2026-11-09): messages, dictation and
/// attachments wait in the outbox under `key`. Once the PC answers, everything goes out in order: the waiting messages
/// together as the first prompt of a new agent in the vault folder, later ones into that same session while it runs.
/// Nothing twice: sends carry the item's `client_id`, and a launch whose answer got lost is found again by the tag in
/// the session's name instead of starting a second agent.
public enum VaultChat {
    /// Outbox key of the vault chat (no session exists yet).
    public static let key = "vault:chat"
    public static let title = "Vault-Agent"
    public static let openButton = "Nachricht an Vault-Agent"
    public static let offlineInfo = "Keine Verbindung zum PC. Schreib, diktiere oder hänge etwas an: Es wartet hier und geht an den Agenten im Vault, sobald der PC erreichbar ist."
    public static let onlineInfo = "Nachrichten gehen an den Agenten im Vault. Ist der PC nicht erreichbar, warten sie hier und gehen später der Reihe nach raus."
    public static let namePrefix = "Vom iPhone"

    public static func isVault(_ key: String) -> Bool { key == Self.key }

    /// Six characters from the first message's id, part of the session name.
    public static func tag(_ id: String) -> String {
        String(id.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }

    /// "Vom iPhone 3fa9c2".
    public static func sessionName(tag: String) -> String { "\(namePrefix) \(tag)" }

    /// The messages that go out together when a new agent starts: every waiting vault message, in order (`next` is
    /// first, it is the oldest one still waiting).
    public static func batch(_ items: [OutItem], next: OutItem) -> [OutItem] {
        [next] + items.filter { $0.id != next.id && isVault($0.key) && $0.state == .queued }
    }

    /// A session started for this batch earlier (launch done, answer lost): found by the tag in its name.
    public static func launched(_ sessions: [(key: String, name: String)], tag: String) -> String? {
        guard !tag.isEmpty else { return nil }
        return sessions.first { $0.name == sessionName(tag: tag) }?.key
    }

    /// The agent of the last batch still runs: further messages go there instead of starting another one.
    public static func reusable(alive: Bool, closed: Bool, hibernated: Bool) -> Bool { alive && !closed && !hibernated }

    /// "Anhang: 3fa9c2-foto.jpg" is stored under a unique name; shown and uploaded without the prefix.
    public static func displayName(_ stored: String) -> String {
        guard let dash = stored.firstIndex(of: "-"), stored.distance(from: stored.startIndex, to: dash) == 8 else { return stored }
        return String(stored[stored.index(after: dash)...])
    }

    public static func storedName(id: String, name: String) -> String {
        let clean = name.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespaces)
        return String(id.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(8)).padding(toLength: 8, withPad: "0", startingAt: 0)
            + "-" + (clean.isEmpty ? "datei" : clean)
    }

    /// One message with the PC paths of its uploaded attachments.
    public static func body(_ text: String, paths: [String]) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = paths.map { "Anhang: \($0)" }.joined(separator: "\n")
        return t.isEmpty ? p : (p.isEmpty ? t : t + "\n" + p)
    }

    /// When the message was written: "09.11. 15:42".
    public static func stamp(_ at: Double, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = timeZone
        f.dateFormat = "dd.MM. HH:mm"
        return f.string(from: Date(timeIntervalSince1970: at))
    }

    /// The first prompt of a new vault agent: the waiting messages with the time they were written, in order.
    public static func prompt(_ messages: [(at: Double, text: String)], timeZone: TimeZone = .current) -> String {
        var lines: [String]
        if messages.count == 1 {
            lines = ["Nachricht vom iPhone (Vault-Chat in Relay, geschrieben \(stamp(messages[0].at, timeZone: timeZone))):", "",
                     messages[0].text]
        } else {
            lines = ["\(messages.count) Nachrichten vom iPhone (Vault-Chat in Relay), in der Reihenfolge, in der sie geschrieben wurden:"]
            for (n, m) in messages.enumerated() {
                lines += ["", "\(n + 1). (\(stamp(m.at, timeZone: timeZone)))", m.text]
            }
        }
        lines += ["", "Bearbeite das der Reihe nach. Halte dich an die AGENTS.md des Vaults. Anhänge liegen unter den genannten Pfaden auf dem PC."]
        return lines.joined(separator: "\n")
    }

    /// A message that came later, while the agent of this chat runs.
    public static func followUp(_ text: String, at: Double, timeZone: TimeZone = .current) -> String {
        "Nachricht vom iPhone (Vault-Chat, \(stamp(at, timeZone: timeZone))):\n\(text)"
    }
}
