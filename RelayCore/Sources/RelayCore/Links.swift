import Foundation

/// A link found in a message: `label` as shown (the URL itself for a bare one), `target` as written.
public struct FoundLink: Sendable, Hashable {
    public let label: String, target: String
    public init(label: String, target: String) { self.label = label; self.target = target }
}

/// Where a tapped link goes.
public enum LinkTarget: Sendable, Hashable {
    case web(String)
    /// A file on the PC: an absolute path (or a relative one when no folder was known), with an optional line.
    case file(String, line: Int?)
    /// Another scheme (mailto:, tel:, ...): handed to iOS.
    case other(String)
    case none
}

enum Rx {
    static func make(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression {
        // patterns are constants; a bad one is a programming error caught by the tests
        try! NSRegularExpression(pattern: p, options: o)
    }
    static func matches(_ r: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
        r.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
    static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : (s as NSString).substring(with: r)
    }
    static func fullMatch(_ r: NSRegularExpression, _ s: String) -> Bool {
        let n = (s as NSString).length
        guard let m = r.firstMatch(in: s, range: NSRange(location: 0, length: n)) else { return false }
        return m.range.location == 0 && m.range.length == n
    }
}

public enum Links {
    private static let mdLink = Rx.make("(?<!!)\\[([^\\]\\n]*)\\]\\(\\s*<?([^)\\s>]+)>?(?:\\s+\"[^\"]*\")?\\s*\\)")
    private static let image = Rx.make("!\\[[^\\]\\n]*\\]\\([^)\\n]*\\)")
    private static let angle = Rx.make("<((?:https?://|www\\.)[^>\\s]+)>", .caseInsensitive)
    private static let bare = Rx.make("(?<![\\w@/.-])(?:https?://|www\\.)(?:[^\\s<>()\\[\\]\"'`{}|\\\\^]|\\([^\\s()]*\\))+", .caseInsensitive)
    private static let trail: Set<Character> = [".", ",", ";", ":", "!", "?", "*", "_", "~", "'", "\""]

    private static func overlaps(_ a: NSRange, _ b: NSRange) -> Bool {
        a.location < b.location + b.length && b.location < a.location + a.length
    }

    /// Every link of a markdown text in order of appearance, each target once: markdown links (also to files),
    /// `<url>` autolinks and bare http(s) / www. URLs, code included. Images and in-page anchors are left out.
    public static func extract(_ md: String) -> [FoundLink] {
        var found: [(Int, FoundLink)] = []
        var taken: [NSRange] = Rx.matches(image, md).map(\.range)
        for m in Rx.matches(mdLink, md) {
            let target = Rx.group(m, 2, in: md)
            taken.append(m.range)
            if target.hasPrefix("#") { continue }
            let label = MdText.plain(Rx.group(m, 1, in: md))
            found.append((m.range.location, FoundLink(label: label.isEmpty ? target : label, target: target)))
        }
        for m in Rx.matches(angle, md) where !taken.contains(where: { overlaps($0, m.range) }) {
            taken.append(m.range)
            let u = Rx.group(m, 1, in: md)
            found.append((m.range.location, FoundLink(label: u, target: u)))
        }
        for m in Rx.matches(bare, md) where !taken.contains(where: { overlaps($0, m.range) }) {
            let url = trimUrl((md as NSString).substring(with: m.range))
            if url.count < 8 { continue }
            found.append((m.range.location, FoundLink(label: url, target: url)))
        }
        var seen = Set<String>()
        return found.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0.target).inserted }
    }

    /// Bare http(s) and www. URLs in plain text as (utf16 start, utf16 end, url).
    public static func bareUrls(_ text: String) -> [(start: Int, end: Int, url: String)] {
        Rx.matches(bare, text).compactMap { m in
            let u = trimUrl((text as NSString).substring(with: m.range))
            return u.count >= 8 ? (m.range.location, m.range.location + (u as NSString).length, u) : nil
        }
    }

    /// A bare URL without the punctuation that ends the sentence around it; a closing parenthesis only with its opening one.
    public static func trimUrl(_ raw: String) -> String {
        var s = raw
        while let c = s.last {
            if trail.contains(c) { s.removeLast() }
            else if c == ")" && s.filter({ $0 == "(" }).count < s.filter({ $0 == ")" }).count { s.removeLast() }
            else { break }
        }
        return s
    }
}

public enum LinkTargets {
    private static let scheme = Rx.make("^[a-zA-Z][a-zA-Z0-9+.-]*:")
    private static let nameLine = Rx.make("^[^:/]+:\\d+(?::\\d+)?(?:-\\d+)?$")
    private static let lineSchemes: Set<String> = ["tel", "sms", "smsto", "mailto", "geo", "fax"]
    private static let anchorLine = Rx.make("#L(\\d+)(?:C\\d+)?(?:-L?\\d+(?:C\\d+)?)?$")
    private static let colonLine = Rx.make(":(\\d+)(?::\\d+)?(?:-\\d+)?$")

    /// Classifies a link target from a reply. File links (`[a.kt:42](src/a.kt#L42)`) lose their line suffix and resolve
    /// against `base` (the session's folder); `~/` expands to the home folder taken from `base` (`/home/<user>`).
    public static func resolve(_ raw: String, base: String? = nil) -> LinkTarget {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("<") { t.removeFirst() }
        if t.hasSuffix(">") { t.removeLast() }
        if t.isEmpty || t.hasPrefix("#") { return .none }
        let lower = t.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return .web(t) }
        if lower.hasPrefix("www.") { return .web("https://" + t) }
        if lower.hasPrefix("file://") {
            var rest = String(t.dropFirst(7))
            if rest.hasPrefix("localhost/") { rest = String(rest.dropFirst(9)) }
            return file(decode(rest), base)
        }
        if !Rx.matches(scheme, t).isEmpty {
            let sch = String(t.prefix(while: { $0 != ":" })).lowercased()
            if !(Rx.fullMatch(nameLine, t) && !lineSchemes.contains(sch)) { return .other(t) }
        }
        return file(decode(t), base)
    }

    private static func file(_ p: String, _ base: String?) -> LinkTarget {
        var path = String(p.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        var line: Int?
        if let m = Rx.matches(anchorLine, path).first {
            line = Int(Rx.group(m, 1, in: path))
            path = (path as NSString).substring(to: m.range.location)
        }
        path = String(path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        if line == nil, let m = Rx.matches(colonLine, path).first {
            line = Int(Rx.group(m, 1, in: path))
            path = (path as NSString).substring(to: m.range.location)
        }
        if path.trimmingCharacters(in: .whitespaces).isEmpty { return .none }
        let h = home(base)
        var abs: String
        if path == "~" || path.hasPrefix("~/") { abs = h.map { $0 + path.dropFirst() } ?? path }
        else if path.hasPrefix("/") { abs = path }
        else if let b = base { abs = (b.hasSuffix("/") ? String(b.dropLast()) : b) + "/" + path }
        else { abs = path }
        if abs.hasPrefix("~") { return .file(abs, line: line) }
        return .file(normalize(abs), line: line)
    }

    /// `/home/<user>` (or `/root`) of a path on the PC, nil when it is not under one.
    public static func home(_ path: String?) -> String? {
        guard let p = path else { return nil }
        if p == "/root" || p.hasPrefix("/root/") { return "/root" }
        let parts = p.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count >= 3, parts[0].isEmpty, parts[1] == "home", !parts[2].isEmpty { return "/home/" + parts[2] }
        return nil
    }

    /// `a/./b/../c` -> `a/c`; leading `..` of a relative path stay.
    public static func normalize(_ path: String) -> String {
        let abs = path.hasPrefix("/")
        var out: [Substring] = []
        for seg in path.split(separator: "/", omittingEmptySubsequences: false) {
            if seg.isEmpty || seg == "." { continue }
            if seg == ".." { if let l = out.last, l != ".." { out.removeLast() } else if !abs { out.append(seg) } }
            else { out.append(seg) }
        }
        return (abs ? "/" : "") + out.joined(separator: "/")
    }

    /// %XX escapes decoded as UTF-8; an invalid escape stays as written.
    public static func decode(_ s: String) -> String {
        guard s.contains("%") else { return s }
        var bytes: [UInt8] = []
        let u = Array(s.utf8)
        var i = 0
        func hex(_ b: UInt8) -> UInt8? {
            switch b { case 48...57: return b - 48; case 65...70: return b - 55; case 97...102: return b - 87; default: return nil }
        }
        while i < u.count {
            if u[i] == 37, i + 2 < u.count, let a = hex(u[i + 1]), let b = hex(u[i + 2]) {
                bytes.append(a * 16 + b); i += 3
            } else { bytes.append(u[i]); i += 1 }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Inline marks removed: a link label or table cell as plain text.
public enum MdText {
    private static let link = Rx.make("!?\\[([^\\]]*)\\]\\([^)]*\\)")
    private static let bold = Rx.make("(\\*\\*|__)(.+?)\\1")
    private static let ital = Rx.make("(?<![\\w*])\\*(?!\\s)([^*\\n]+?)\\*(?![\\w*])")
    private static let code = Rx.make("`([^`]*)`")
    private static let tag = Rx.make("</?(br|b|i|strong|em|code)\\s*/?>", .caseInsensitive)

    private static func sub(_ r: NSRegularExpression, _ s: String, _ t: String) -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: t)
    }

    public static func plain(_ s: String) -> String {
        var r = sub(tag, s, " ")
        r = sub(link, r, "$1")
        r = sub(code, r, "$1")
        r = sub(bold, r, "$2")
        r = sub(ital, r, "$1")
        return r.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
