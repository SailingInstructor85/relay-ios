import Foundation

/// Search in the overview and over the whole app (port of Android SessionSearch.kt, AppSearch.kt).
public enum ContentSearch {
    /// Pause after the last keystroke before the Desktop is asked.
    public static let pauseMs = 400
    public static let minChars = 2
    public static let days = 7

    public static func wanted(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= minChars
    }

    public struct Hit: Sendable, Hashable, Identifiable {
        public var id: String { sessionKey }
        public let sessionKey: String, tool: String, alias: String, role: String, snippet: String, ts: Double
        public init(sessionKey: String, tool: String, alias: String, role: String, snippet: String, ts: Double) {
            self.sessionKey = sessionKey; self.tool = tool; self.alias = alias; self.role = role; self.snippet = snippet; self.ts = ts
        }
    }

    /// `search_transcripts` answer: `{"hits":[{session_key, tool, alias, role, snippet, ts}]}`; one hit per session, newest first.
    public static func hits(_ r: JSON) -> [Hit] {
        var seen = Set<String>()
        var out: [Hit] = []
        for h in r["hits"].array {
            let k = h.str("session_key")
            guard !k.isEmpty, seen.insert(k).inserted else { continue }
            out.append(Hit(sessionKey: k, tool: h.str("tool"), alias: h.str("alias"), role: h.str("role"),
                           snippet: h.str("snippet"), ts: h.num("ts")))
        }
        return out.sorted { $0.ts > $1.ts }
    }

    /// Hits named after their session; only sessions in the list count (headless runs, summaries and Jarvis runs are left out).
    public static func conversations(_ hits: [Hit], sessions: [Session]) -> [(session: Session, hit: Hit)] {
        let visible = sessions.filter { !$0.background }
        return hits.compactMap { h in
            guard let s = visible.first(where: { $0.matches(h.sessionKey) }) else { return nil }
            return (s, h)
        }
    }
}

public enum AppSearch {
    public static let max = 20

    /// Every word of the query occurs in the text (any case, accents ignored).
    public static func matches(_ text: String, _ query: String) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return false }
        return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Sessions by title and folder (fuzzy, as in the overview), best first, newest on ties.
    public static func sessions(_ sessions: [Session], query: String) -> [Session] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let scored = sessions.filter { !$0.background }.compactMap { s -> (Session, Int)? in
            Fuzzy.score(q, "\(s.name) \(s.alias) \(s.folder) \(s.cwd)").map { (s, $0) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.lastActivity > $1.0.lastActivity }.prefix(max).map(\.0)
    }

    /// Jarvis turns of this phone, newest first.
    public static func jarvis(_ turns: [JarvisTurn], query: String) -> [JarvisTurn] {
        Array(turns.reversed().filter { matches($0.q + "\n" + $0.a, query) }.prefix(max))
    }

    /// A short piece of `text` around the first occurrence of the first query word.
    public static func snippet(_ text: String, query: String, width: Int = 120) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let w = query.split(whereSeparator: { $0.isWhitespace }).first,
              let r = flat.range(of: String(w), options: [.caseInsensitive, .diacriticInsensitive]) else { return String(flat.prefix(width)) }
        let at = flat.distance(from: flat.startIndex, to: r.lowerBound)
        let from = Swift.max(0, at - width / 3)
        let s = flat.index(flat.startIndex, offsetBy: from)
        let e = flat.index(s, offsetBy: Swift.min(width, flat.distance(from: s, to: flat.endIndex)))
        return (from > 0 ? "…" : "") + flat[s..<e] + (e < flat.endIndex ? "…" : "")
    }
}

/// "Share to a session" (port of Android Share.kt, ShareLogic).
public enum ShareLogic {
    public static let maxBytes = 50 * 1024 * 1024

    /// "<message>\n\n<path>\n<path>"; without files the shared text is the body.
    public static func body(message: String, paths: [String], text: String?) -> String {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = paths.isEmpty ? (text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") : paths.joined(separator: "\n")
        if m.isEmpty { return rest }
        return rest.isEmpty ? m : "\(m)\n\n\(rest)"
    }

    public static func canSend(files: Int, text: String?, message: String) -> Bool {
        files > 0 || !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func cleanName(_ raw: String?, ext: String?, n: Int) -> String {
        let base = (raw ?? "").split(separator: "/").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        if !base.isEmpty { return String(base.prefix(120)) }
        let e = (ext ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return "shared-\(n)" + (e.isEmpty ? "" : ".\(e)")
    }

    public static func sizeLabel(_ bytes: Int) -> String {
        if bytes < 0 { return "" }
        if bytes >= 1 << 20 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return "\(bytes / 1024) KB" }
        return "\(bytes) B"
    }

    /// Sessions that can receive a share: running ones, the last opened first, then waiting, then newest; filtered by query.
    public static func targets(_ sessions: [Session], lastKey: String, query: String) -> [Session] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let live = sessions.filter { !$0.background && !$0.exited && !$0.closed && !$0.hibernated && !$0.placeholder }
        let hit = live.compactMap { s -> (Session, Int)? in
            q.isEmpty ? (s, 0) : Fuzzy.score(q, "\(s.name) \(s.alias) \(s.folder) \(s.cwd)").map { (s, $0) }
        }
        let sorted = hit.sorted { a, b in
            if a.0.matches(lastKey) != b.0.matches(lastKey) { return a.0.matches(lastKey) }
            if !q.isEmpty && a.1 != b.1 { return a.1 > b.1 }
            if a.0.waits != b.0.waits { return a.0.waits }
            return a.0.lastActivity > b.0.lastActivity
        }
        return sorted.map(\.0)
    }
}

/// "Ins Vault einsortieren": a share target without a session. The files go to the Desktop as uploads; a new agent
/// session in the vault folder moves them to the inbox folder first and then files them by content (the vault's own
/// AGENTS.md says how).
public enum VaultDrop {
    public static let defaultDir = "~/Dokumente/zweites-gehirn/zweites Gehirn"
    public static let inbox = "01 Inbox"
    public static let attachments = "07 Anhänge"

    /// Session name: "Ablage: daniel.pdf" or "Ablage: 3 Dateien".
    public static func name(paths: [String]) -> String {
        if paths.count == 1 { return "Ablage: " + (paths[0] as NSString).lastPathComponent }
        return "Ablage: \(paths.count) Dateien"
    }

    /// The first message of the filing agent.
    public static func prompt(paths: [String], note: String) -> String {
        var lines = ["Neue Dokumente vom iPhone zum Einsortieren ins Vault.", "", "Dateien (Uploads des Gateways):"]
        lines += paths.map { "- \($0)" }
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { lines += ["", "Hinweis von Martin: \(n)"] }
        lines += ["", "Vorgehen:",
                  "1. Verschiebe jede Datei zuerst nach \"\(inbox)/\" in diesem Vault (verschieben, nicht kopieren).",
                  "2. Lies sie und erkenne, worum es geht.",
                  "3. Sortiere sie ein: die Datei nach \"\(attachments)/\", dazu eine kurze Notiz oder ein Link im passenden Bereich. Halte dich an die AGENTS.md des Vaults.",
                  "4. Melde am Ende knapp: welche Datei, wohin, warum."]
        return lines.joined(separator: "\n")
    }
}

/// Wording of the connection state (Android A10): "Kein Weg zum PC" instead of "Offline" when a private LAN address is
/// configured and no VPN is up. Words only, nothing is blocked.
public enum ConnText {
    public static func isPrivateLAN(_ host: String) -> Bool {
        let p = host.trimmingCharacters(in: .whitespaces).split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        if p[0] == 10 { return true }
        if p[0] == 172 && (16...31).contains(p[1]) { return true }
        return p[0] == 192 && p[1] == 168
    }

    public static func noRoute(host: String, vpn: Bool) -> Bool { isPrivateLAN(host) && !vpn }
    /// With a second address (a VPN one) there may be a way after all: only when every address is a private LAN one.
    public static func noRoute(hosts: [String], vpn: Bool) -> Bool { !hosts.isEmpty && hosts.allSatisfy(isPrivateLAN) && !vpn }
    public static let noRouteText = "Kein Weg zum PC (privates Netz, kein VPN)"
}

/// Favourite folders and the last used account for "Neue Sitzung" (Android D2).
public enum FavDirs {
    public static func toggled(_ favs: [String], _ path: String) -> [String] {
        favs.contains(path) ? favs.filter { $0 != path } : favs + [path]
    }
    /// Favourites first (in the order given), then the rest of the recent folders without duplicates.
    public static func ordered(favs: [String], recent: [String]) -> [String] {
        favs + recent.filter { !favs.contains($0) }
    }
    public static func decode(_ raw: String) -> [String] { raw.split(separator: "\n").map(String.init) }
    public static func encode(_ list: [String]) -> String { list.joined(separator: "\n") }
}

/// "Stand" in the chat header: the relative time, with the clock read fresh (not from a timer that slept).
public enum StandText {
    public static func text(lastActivity: Double, now: Date = Date()) -> String {
        guard lastActivity > 0 else { return "" }
        let t = TermText.ago(lastActivity, now: now)
        return t == "jetzt" ? "Stand: jetzt" : "Stand: vor \(t)"
    }
}

/// The phone's profile (`profile_get` / `profile_set`; Android AutofillProfile.kt).
public enum ProfileFields {
    public static let all: [(key: String, label: String)] = [
        ("full_name", "Name"), ("first_name", "Vorname"), ("last_name", "Nachname"), ("birthday", "Geburtstag"),
        ("phone", "Telefon"), ("street", "Straße"), ("house_number", "Hausnummer"), ("postcode", "PLZ"), ("city", "Ort"),
        ("country", "Land"), ("driving_licence", "Führerschein"), ("id_number", "Ausweisnummer"),
    ]

    /// Fields (emails comma-separated) from the `profile` object.
    public static func values(_ profile: JSON) -> (fields: [String: String], emails: [String]) {
        var f: [String: String] = [:]
        for (k, _) in all { f[k] = profile.str(k) }
        return (f, profile["emails"].array.compactMap(\.string))
    }

    /// The `profile` object to save; empty fields are dropped.
    public static func make(fields: [String: String], emails: [String]) -> JSON {
        var o: [String: JSON] = [:]
        for (k, _) in all {
            let v = (fields[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { o[k] = .string(v) }
        }
        let e = emails.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !e.isEmpty { o["emails"] = .array(e.map { .string($0) }) }
        return .object(o)
    }

    public static func splitEmails(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace }).map(String.init)
    }

    /// Looks like a card or IBAN number (the gateway refuses them anyway): warn before sending.
    public static func looksSensitive(_ s: String) -> Bool {
        let digits = s.filter(\.isNumber)
        if digits.count >= 13 && digits.count <= 19 && s.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }) { return true }
        let compact = s.replacingOccurrences(of: " ", with: "").uppercased()
        return compact.count >= 15 && compact.count <= 34 && compact.prefix(2).allSatisfy(\.isLetter) && compact.dropFirst(2).prefix(2).allSatisfy(\.isNumber)
    }
}
