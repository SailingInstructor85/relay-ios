import Foundation

/// Ein Link in einem Mailtext. Mailtext ist fremd: Die App öffnet einen Link nur auf Tippen, nie von selbst, und
/// nur http, https und mailto. `warning` ist gesetzt, wenn das, was im Text steht, über das Ziel täuschen kann;
/// dann zeigt die App zuerst die echte Zieladresse.
public struct MailLink: Sendable, Equatable, Identifiable {
    /// Stelle im Text in UTF-16-Einheiten (wie `NSRange`).
    public let start: Int
    public let end: Int
    /// So steht es in der Mail.
    public let shown: String
    /// Das wird geöffnet (https://…, http://… oder mailto:…).
    public let target: String
    /// Rechnername des Ziels, bei mailto die Adresse.
    public let host: String
    public let warning: String?

    public var id: Int { start }
    public var isMail: Bool { target.lowercased().hasPrefix("mailto:") }

    public init(start: Int, end: Int, shown: String, target: String, host: String, warning: String? = nil) {
        self.start = start; self.end = end; self.shown = shown; self.target = target; self.host = host; self.warning = warning
    }
}

public enum MailLinks {
    private static let email = Rx.make(
        "(?<![\\w.+-])(?:mailto:)?([A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,})", .caseInsensitive)
    private static let domain = Rx.make(
        "(?<![\\w@.-])(?:https?://)?((?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,})(?![\\w-])", .caseInsensitive)
    private static let ipv4 = Rx.make("^\\d{1,3}(?:\\.\\d{1,3}){3}$")

    /// Nur diese Arten von Zielen öffnet die App aus einer Mail.
    public static func allowed(_ target: String) -> Bool {
        let t = target.lowercased()
        return t.hasPrefix("https://") || t.hasPrefix("http://") || t.hasPrefix("mailto:")
    }

    /// Alle Links eines Mailtexts in der Reihenfolge des Texts: Webadressen (http, https, www.) und Mailadressen.
    public static func find(_ text: String) -> [MailLink] {
        let ns = text as NSString
        var out: [MailLink] = []
        for u in Links.bareUrls(text) {
            let target = u.url.lowercased().hasPrefix("www.") ? "https://" + u.url : u.url
            guard allowed(target), let p = parts(target), !p.host.isEmpty else { continue }
            let note = warning(host: p.host, userinfo: p.userinfo, before: lineBefore(ns, u.start))
            out.append(MailLink(start: u.start, end: u.end, shown: u.url, target: target, host: p.host, warning: note))
        }
        for m in Rx.matches(email, text) {
            let r = m.range
            if out.contains(where: { $0.start < r.location + r.length && r.location < $0.end }) { continue }
            let address = Rx.group(m, 1, in: text)
            out.append(MailLink(start: r.location, end: r.location + r.length, shown: ns.substring(with: r),
                                target: "mailto:" + address, host: address))
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Anmeldeteil (vor dem @) und Rechnername einer Webadresse, ohne Port, klein geschrieben.
    static func parts(_ target: String) -> (userinfo: String?, host: String)? {
        guard let r = target.range(of: "://") else { return nil }
        var authority = String(target[r.upperBound...])
        if let end = authority.firstIndex(where: { "/?#\\".contains($0) }) { authority = String(authority[..<end]) }
        var userinfo: String?
        if let at = authority.lastIndex(of: "@") {
            userinfo = String(authority[..<at])
            authority = String(authority[authority.index(after: at)...])
        }
        if authority.hasPrefix("[") {
            if let close = authority.firstIndex(of: "]") { authority = String(authority[...close]) }
        } else if let colon = authority.lastIndex(of: ":") {
            authority = String(authority[..<colon])
        }
        return (userinfo, authority.lowercased())
    }

    /// Der Text derselben Zeile vor einer Stelle, höchstens 120 Zeichen.
    static func lineBefore(_ ns: NSString, _ start: Int) -> String {
        let from = max(0, start - 120)
        let chunk = ns.substring(with: NSRange(location: from, length: start - from))
        if let nl = chunk.lastIndex(where: { $0 == "\n" || $0 == "\r" }) { return String(chunk[chunk.index(after: nl)...]) }
        return chunk
    }

    /// Gehören zwei Rechnernamen zusammen (gleich, oder einer liegt unter dem anderen)? „www.“ zählt nicht.
    static func related(_ a: String, _ b: String) -> Bool {
        func bare(_ s: String) -> String { let l = s.lowercased(); return l.hasPrefix("www.") ? String(l.dropFirst(4)) : l }
        let x = bare(a), y = bare(b)
        return x == y || x.hasSuffix("." + y) || y.hasSuffix("." + x)
    }

    /// Warum der Text über das Ziel täuschen kann, nil wenn nichts auffällt.
    static func warning(host: String, userinfo: String?, before: String) -> String? {
        if let u = userinfo {
            let name = u.split(separator: ":").first.map(String.init) ?? u
            return "Die Adresse beginnt mit „\(name)“, führt aber zu \(host)."
        }
        if host.hasPrefix("[") || Rx.fullMatch(ipv4, host) {
            return "Das Ziel ist eine Zahlenadresse (\(host)), kein Name."
        }
        if host.split(separator: ".").contains(where: { $0.hasPrefix("xn--") }) || host.unicodeScalars.contains(where: { !$0.isASCII }) {
            return "Der Name des Ziels enthält Sonderzeichen, die wie andere Buchstaben aussehen können: \(host)."
        }
        // „www.bank.example <https://anders.example/…>“ oder „[bank.example](https://anders.example)“: Der Text
        // direkt vor dem eingeklammerten Link nennt eine andere Adresse.
        var lead = before.trimmingCharacters(in: .whitespaces)
        guard let open = lead.last, "<([".contains(open) else { return nil }
        lead.removeLast()
        guard let word = lead.split(whereSeparator: { $0 == " " || $0 == "\t" }).last.map(String.init) else { return nil }
        guard let m = Rx.matches(domain, word).last else { return nil }
        let named = Rx.group(m, 1, in: word).lowercased()
        return related(named, host) ? nil : "Im Text steht \(named), der Link führt aber zu \(host)."
    }
}
