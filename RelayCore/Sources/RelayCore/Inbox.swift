import Foundation

// Posteingang (PROTOCOL.md des Gateways, RPCs `inbox_feed`, `inbox_search`, `inbox_mail`, `inbox_mail_suggest`; Code in
// gateway/src/notifyd/inbox.py und mailsuggest.py). Nur lesend: Die App sendet, löscht und beantwortet nichts.
// Alle Texte aus Mails sind fremde Inhalte und werden nur als reiner Text gezeigt.

/// Eine Zeile des Posteingangs: eine Mail oder ein Chat (ein Chat je Zeile, mit seiner neuesten Nachricht).
public struct InboxItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case mail, chat }

    public let kind: Kind
    /// Mail: die Nummer im Index (nur Ziffern). Chat: `<paket>|<chat>` oder `sms|<name>`.
    public let itemID: String
    /// `mail` oder der Messenger (`whatsapp`, `telegram`, `threema`, `signal`, `sms`).
    public let source: String
    /// Mail: Name des Kontos (bei Suchtreffern auch „Archive“).
    public let account: String
    /// Mail: Name des Absenders (Suchtreffer aus „Gesendet“: „To <Empfänger>“). Chat: Name des Chats.
    public let title: String
    public let from: String
    public let subject: String
    public let ts: Double
    public let attachments: Bool
    /// Nur Suchtreffer: der passende Text aus der Mail.
    public let snippet: String
    /// Nur Suchtreffer: eine eigene, gesendete Mail.
    public let sent: Bool
    /// Chat: Name der App.
    public let appLabel: String
    /// Chat: Absender der neuesten Nachricht.
    public let sender: String
    /// Chat: die neueste Nachricht.
    public let text: String
    /// Chat: Zahl der Nachrichten.
    public let count: Int

    public var id: String { kind.rawValue + ":" + itemID }

    public init(kind: Kind, itemID: String, source: String = "mail", account: String = "", title: String = "", from: String = "",
                subject: String = "", ts: Double = 0, attachments: Bool = false, snippet: String = "", sent: Bool = false,
                appLabel: String = "", sender: String = "", text: String = "", count: Int = 0) {
        self.kind = kind; self.itemID = itemID; self.source = source; self.account = account; self.title = title; self.from = from
        self.subject = subject; self.ts = ts; self.attachments = attachments; self.snippet = snippet; self.sent = sent
        self.appLabel = appLabel; self.sender = sender; self.text = text; self.count = count
    }

    /// Eine Zeile aus `items` von `inbox_feed` oder `inbox_search`. Unbekannte Arten und Zeilen ohne `id` entfallen.
    public static func from(_ o: JSON) -> InboxItem? {
        guard let kind = Kind(rawValue: o.str("type")) else { return nil }
        let id = o.str("id")
        guard !id.isEmpty else { return nil }
        return InboxItem(kind: kind, itemID: id, source: o.str("source", kind == .mail ? "mail" : ""), account: o.str("account"),
                         title: o.str("title"), from: o.str("from"), subject: o.str("subject"), ts: o.num("ts"),
                         attachments: o.flag("attachments"), snippet: o.str("snippet"), sent: o.flag("sent"),
                         appLabel: o.str("app_label"), sender: o.str("sender"), text: o.str("text"), count: o["count"].int ?? 0)
    }

    /// Erste Zeile: wer. Ohne Namen die Adresse, sonst „?“.
    public var who: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let f = from.trimmingCharacters(in: .whitespacesAndNewlines)
        return f.isEmpty ? "?" : f
    }

    /// Zweite Zeile: bei Mail der Betreff, bei einem Chat entfällt sie.
    public var headline: String {
        guard kind == .mail else { return "" }
        let s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? InboxText.noSubject : s
    }

    /// Vorschau, auf eine Zeile geglättet. Der Feed liefert für Mail keinen Text, nur die Suche (`snippet`); bei einem
    /// Chat ist es die neueste Nachricht mit Absender.
    public var preview: String {
        switch kind {
        case .mail: return Today.flat(snippet)
        case .chat:
            let t = Today.flat(text)
            let s = sender.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty || s == title ? t : "\(s): \(t)"
        }
    }

    /// Kleine Zeile unten: Konto oder App, dazu „Gesendet“ und bei Chats die Zahl der Nachrichten.
    public var footer: String {
        var parts: [String] = []
        let label = kind == .mail ? account : (appLabel.isEmpty ? source : appLabel)
        if !label.isEmpty { parts.append(label == "Archive" ? "Archiv" : label) }
        if sent { parts.append("Gesendet") }
        if kind == .chat, count > 1 { parts.append("\(count) Nachrichten") }
        return parts.joined(separator: " · ")
    }

    /// Text, aus dem Kürzel und Farbe des Kreises entstehen: die Adresse, sonst der Name.
    public var avatarKey: String { from.isEmpty ? title : InboxText.address(from) }
}

/// Antwort von `inbox_feed`.
public struct InboxFeed: Sendable, Equatable {
    public let items: [InboxItem]
    public let days: Int
    /// Fehler der Mailquelle (`errors.mail`), leer wenn sie geliefert hat.
    public let mailError: String
    /// Fehler der Chatquelle (`errors.messages`).
    public let messagesError: String

    public init(items: [InboxItem], days: Int = 7, mailError: String = "", messagesError: String = "") {
        self.items = items; self.days = days; self.mailError = mailError; self.messagesError = messagesError
    }

    public static func from(_ o: JSON) -> InboxFeed {
        InboxFeed(items: o["items"].array.compactMap(InboxItem.from), days: o["days"].int ?? 7,
                  mailError: o["errors"].str("mail"), messagesError: o["errors"].str("messages"))
    }
}

/// Antwort von `inbox_search`: Treffer über alle Jahre, neueste zuerst.
public struct InboxSearchResult: Sendable, Equatable {
    public let items: [InboxItem]
    public let query: String
    /// Wie viele Mails der Index insgesamt zu der Suche hat.
    public let mailTotal: Int
    public let mailError: String
    public let messagesError: String

    public init(items: [InboxItem], query: String, mailTotal: Int = 0, mailError: String = "", messagesError: String = "") {
        self.items = items; self.query = query; self.mailTotal = mailTotal; self.mailError = mailError; self.messagesError = messagesError
    }

    public static func from(_ o: JSON) -> InboxSearchResult {
        let items = o["items"].array.compactMap(InboxItem.from)
        return InboxSearchResult(items: items, query: o.str("q"), mailTotal: o["mail_total"].int ?? items.count,
                                 mailError: o["errors"].str("mail"), messagesError: o["errors"].str("messages"))
    }
}

/// Antwort von `inbox_mail`: eine Mail als reiner Text.
public struct MailMessage: Sendable, Equatable, Identifiable {
    public let id: String
    public let ts: Double
    public let from: String
    public let to: String
    public let subject: String
    public let account: String
    /// Reiner Text, höchstens 20.000 Zeichen.
    public let body: String
    /// Der Text ist länger, als das Gateway liefert.
    public let truncated: Bool
    /// Namen der Anhänge.
    public let attachments: [String]

    public init(id: String, ts: Double = 0, from: String = "", to: String = "", subject: String = "", account: String = "",
                body: String = "", truncated: Bool = false, attachments: [String] = []) {
        self.id = id; self.ts = ts; self.from = from; self.to = to; self.subject = subject; self.account = account
        self.body = body; self.truncated = truncated; self.attachments = attachments
    }

    public static func from(_ o: JSON) -> MailMessage? {
        let id = o.str("id")
        guard !id.isEmpty else { return nil }
        return MailMessage(id: id, ts: o.num("ts"), from: o.str("from"), to: o.str("to"), subject: o.str("subject"),
                           account: o.str("account"), body: o.str("body"), truncated: o.flag("truncated"),
                           attachments: o["attachments"].array.compactMap { $0.string }.filter { !$0.isEmpty })
    }

    public var title: String {
        let s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? InboxText.noSubject : s
    }

    /// Der Text in Absätzen (getrennt durch Leerzeilen), damit lange Mails zeilenweise aufgebaut werden können.
    public var paragraphs: [String] { InboxText.paragraphs(body) }
}

/// Ein Aufräumvorschlag aus `inbox_mail_suggest`: Mails eines automatischen Absenders. Die App zeigt ihn nur an.
public struct MailSuggestion: Sendable, Equatable, Identifiable {
    public struct Mail: Sendable, Equatable, Identifiable {
        public let id: String
        public let subject: String
        public let ts: Double
        public let account: String
        public let size: Int
    }

    public let key: String
    public let sender: String
    public let address: String
    /// `newsletter`, `notifications`, `promotions`, `old promotions`, `social` oder `bounces`.
    public let reason: String
    /// Mails in diesem Vorschlag (höchstens 200).
    public let count: Int
    /// Mails des Absenders insgesamt.
    public let total: Int
    public let firstTs: Double
    public let lastTs: Double
    /// Bis zu drei Betreffs als Beispiel.
    public let examples: [String]
    public let accounts: [String]
    public let bytes: Int
    public let mails: [Mail]

    public var id: String { key }

    public init(key: String, sender: String, address: String = "", reason: String = "", count: Int = 0, total: Int = 0,
                firstTs: Double = 0, lastTs: Double = 0, examples: [String] = [], accounts: [String] = [], bytes: Int = 0,
                mails: [Mail] = []) {
        self.key = key; self.sender = sender; self.address = address; self.reason = reason; self.count = count; self.total = total
        self.firstTs = firstTs; self.lastTs = lastTs; self.examples = examples; self.accounts = accounts; self.bytes = bytes
        self.mails = mails
    }

    public static func from(_ o: JSON) -> MailSuggestion? {
        let key = o.str("key")
        guard !key.isEmpty else { return nil }
        let mails = o["mails"].array.compactMap { m -> Mail? in
            let id = m.str("id")
            return id.isEmpty ? nil : Mail(id: id, subject: m.str("subject"), ts: m.num("ts"), account: m.str("account"), size: m["size"].int ?? 0)
        }
        let count = o["count"].int ?? mails.count
        return MailSuggestion(key: key, sender: o.str("sender", key), address: o.str("address", key), reason: o.str("reason"),
                              count: count, total: max(o["total"].int ?? count, count), firstTs: o.num("first_ts"),
                              lastTs: o.num("last_ts"), examples: o["examples"].array.compactMap { $0.string },
                              accounts: o["accounts"].array.compactMap { $0.string }, bytes: o["bytes"].int ?? 0, mails: mails)
    }

    /// Die Gruppen aus der Antwort von `inbox_mail_suggest` (`groups`), in der Reihenfolge des Gateways.
    public static func list(_ o: JSON) -> [MailSuggestion] { o["groups"].array.compactMap(MailSuggestion.from) }

    /// „42 Mails · Newsletter · 1,2 MB“; die Größe entfällt, wenn das Gateway keine nennt.
    public var line: String {
        var parts = [count == 1 ? "1 Mail" : "\(count) Mails"]
        if total > count { parts[0] += " von \(total)" }
        let r = InboxText.reason(reason)
        if !r.isEmpty { parts.append(r) }
        if bytes > 0 { parts.append(InboxText.size(bytes)) }
        return parts.joined(separator: " · ")
    }
}

/// Die Mails und Chats eines Tages, für die Abschnitte der Liste.
public struct InboxDay: Sendable, Equatable, Identifiable {
    /// `JJJJ-MM-TT`, leer für Einträge ohne Zeit.
    public let day: String
    public let label: String
    public let items: [InboxItem]
    public var id: String { day }
}

public enum InboxText {
    public static let noSubject = "(kein Betreff)"
    public static let searchPlaceholder = "Mails durchsuchen (alle Jahre)"
    public static let searchTooShort = "Mindestens zwei Zeichen eingeben."
    public static let nothingFound = "Nichts gefunden."
    public static let suggestionsTitle = "Aufräumvorschläge"
    public static let suggestionsNote = "Nur zur Ansicht. Gelöscht wird hier nichts."
    public static let missingTitle = "Gateway liefert keinen Posteingang"

    /// Text des Leerzustands: „Nichts in den letzten 7 Tagen.“
    public static func empty(days: Int) -> String {
        days == 1 ? "Nichts seit gestern." : "Nichts in den letzten \(max(days, 1)) Tagen."
    }

    // MARK: Fehler

    public struct Failure: Sendable, Equatable {
        public let title: String
        public let text: String
        /// Das Gateway hat geantwortet, liefert aber keinen Posteingang (RPC fehlt oder Mailprogramm am PC fehlt).
        public let missing: Bool
    }

    /// Das Gateway kennt den RPC nicht (ältere oder fremde Gateways antworten „unknown rpc 'inbox_feed'“).
    public static func isUnknownRpc(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("unknown rpc") || m.contains("unknown method")
    }

    /// Was die Liste zeigt, wenn `inbox_feed` scheitert. `remote`: Das Gateway hat geantwortet und abgelehnt
    /// (`RelayError.remote`), sonst ist die Verbindung das Problem.
    public static func failure(message: String, remote: Bool) -> Failure {
        if remote && isUnknownRpc(message) {
            return Failure(title: missingTitle,
                           text: "Das Gateway auf dem PC kennt den Posteingang nicht. Er erscheint hier, sobald das Gateway ihn anbietet.",
                           missing: true)
        }
        if remote { return Failure(title: missingTitle, text: "Antwort des Gateways: \(message)", missing: true) }
        return Failure(title: "Posteingang nicht geladen", text: message, missing: false)
    }

    /// Der Feed kam an, aber die Mailquelle meldet einen Fehler und es gibt keine Zeile: das Mailprogramm am PC fehlt
    /// oder antwortet nicht. Mit Zeilen (etwa Chats) zeigt die Liste den Fehler nur als Zeile; dann nil.
    public static func sourceFailure(_ feed: InboxFeed) -> Failure? {
        guard feed.items.isEmpty, !feed.mailError.isEmpty else { return nil }
        return Failure(title: missingTitle, text: "Das Mailprogramm am PC liefert nichts: \(feed.mailError)", missing: true)
    }

    // MARK: Suche

    /// Der Suchtext, wie er an `inbox_search` geht: getrimmt, 2 bis 200 Zeichen; sonst nil.
    public static func query(_ text: String) -> String? {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (2...200).contains(q.count) ? q : nil
    }

    /// „3 Treffer für „rechnung““, mit „von 120“, wenn der Index mehr Mails hat, als geliefert wurden.
    public static func found(_ r: InboxSearchResult) -> String {
        let n = r.items.count
        let head = n == 1 ? "1 Treffer" : "\(n) Treffer"
        let mails = r.items.filter { $0.kind == .mail }.count
        let more = r.mailTotal > mails ? " (von \(r.mailTotal) Mails im Index)" : ""
        return "\(head) für „\(r.query)“\(more)"
    }

    // MARK: Absender

    /// „Anna Muster <anna@example.org>“ -> „anna@example.org“ (klein); ohne spitze Klammern der ganze Text.
    public static func address(_ from: String) -> String {
        if let a = from.lastIndex(of: "<"), let b = from.lastIndex(of: ">"), a < b {
            return from[from.index(after: a)..<b].trimmingCharacters(in: .whitespaces).lowercased()
        }
        return from.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Kürzel für den Kreis: „Anna Muster“ -> „AM“, „newsletter@example.org“ -> „N“, leer -> „?“.
    public static func initials(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.hasPrefix("To ") { n = String(n.dropFirst(3)) }
        if let at = n.firstIndex(of: "@") { n = String(n[..<at]) }
        let words = n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.count >= 2 { return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased() }
        return words.first.map { String($0.prefix(1)).uppercased() } ?? "?"
    }

    // MARK: Aufräumvorschläge

    /// Grund eines Vorschlags auf Deutsch; Unbekanntes bleibt, wie es ist.
    public static func reason(_ r: String) -> String {
        switch r {
        case "newsletter": return "Newsletter"
        case "notifications": return "Benachrichtigungen"
        case "promotions": return "Werbung"
        case "old promotions": return "Alte Werbung"
        case "social": return "Soziale Netzwerke"
        case "bounces": return "Zustellberichte"
        default: return r
        }
    }

    /// „340 kB“, „1,2 MB“ (dezimal, deutsches Komma).
    public static func size(_ bytes: Int) -> String {
        if bytes < 1000 { return "\(max(bytes, 0)) B" }
        if bytes < 1_000_000 { return "\(Int((Double(bytes) / 1000).rounded())) kB" }
        let mb = (Double(bytes) / 100_000).rounded() / 10
        return String(format: "%.1f MB", mb).replacingOccurrences(of: ".", with: ",")
    }

    /// Zeile über den Vorschlägen: „12 Absender, 340 Mails“.
    public static func suggestionsSummary(_ groups: [MailSuggestion]) -> String {
        let mails = groups.reduce(0) { $0 + $1.count }
        return "\(groups.count) Absender, \(mails == 1 ? "1 Mail" : "\(mails) Mails")"
    }

    // MARK: Mailtext

    /// Absätze eines Mailtexts: an Leerzeilen getrennt, Zeilenenden vereinheitlicht, leere Absätze entfallen.
    public static func paragraphs(_ body: String) -> [String] {
        let text = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var out: [String] = []
        var current: [Substring] = []
        func flush() {
            if !current.isEmpty { out.append(current.joined(separator: "\n")); current = [] }
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.allSatisfy({ $0.isWhitespace }) { flush() } else { current.append(line) }
        }
        flush()
        return out
    }

    /// „Heute, 09:05“, „Mo., 16. November, 18:40“ für den Kopf einer Mail; leer ohne Zeit.
    public static func when(_ ts: Double, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        guard ts > 0 else { return "" }
        let day = DayText.label(DayText.key(ts: ts, timeZone: timeZone), today: DayText.key(now, timeZone: timeZone))
        return "\(day), \(DayText.clock(ts: ts, timeZone: timeZone))"
    }

    // MARK: Tage

    /// Die Zeilen nach Tag gruppiert, in der Reihenfolge des Gateways (neueste zuerst). Einträge ohne Zeit stehen
    /// unter „Ohne Datum“ am Ende.
    public static func days(_ items: [InboxItem], now: Date = Date(), timeZone: TimeZone = .current) -> [InboxDay] {
        let today = DayText.key(now, timeZone: timeZone)
        var order: [String] = []
        var groups: [String: [InboxItem]] = [:]
        for item in items {
            let day = item.ts > 0 ? DayText.key(ts: item.ts, timeZone: timeZone) : ""
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(item)
        }
        let dated = order.filter { !$0.isEmpty }.sorted(by: >)
        return (dated + (groups[""] == nil ? [] : [""])).map { day in
            InboxDay(day: day, label: day.isEmpty ? "Ohne Datum" : DayText.label(day, today: today), items: groups[day] ?? [])
        }
    }
}

/// Die Markierung „neu“ im Posteingang. Das Gateway meldet nicht, ob eine Mail gelesen ist (der Feed hat kein solches
/// Feld). Die App markiert deshalb selbst: neu ist eine Mail, die seit dem letzten Besuch des Posteingangs eingegangen
/// ist und auf diesem iPhone noch nicht geöffnet wurde. Das ist kein Lesestatus des Postfachs.
public enum InboxSeen {
    /// Beim allerersten Besuch gilt als neu, was jünger als ein Tag ist.
    public static func firstSince(now: Double) -> Double { now - 86400 }

    public static func isNew(_ item: InboxItem, since: Double, opened: Set<String>) -> Bool {
        item.kind == .mail && !item.sent && item.ts > since && !opened.contains(item.itemID)
    }

    public static func newCount(_ items: [InboxItem], since: Double, opened: Set<String>) -> Int {
        items.filter { isNew($0, since: since, opened: opened) }.count
    }

    /// Die gemerkten geöffneten Mails bleiben klein: nur die, die noch im Feed stehen, plus die eben geöffnete.
    public static func prune(_ opened: Set<String>, feed: [InboxItem]) -> Set<String> {
        opened.intersection(Set(feed.map { $0.itemID }))
    }
}
