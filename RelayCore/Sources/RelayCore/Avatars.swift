import Foundation

/// A session's avatar: the project's initials on the project's colour (or a configured emoji). Port of Android's `Avatars`.
public enum Avatars {
    public struct Look: Sendable, Equatable {
        public var map: [String: String] = [:]
        public var colors: [String: UInt32] = [:]
        public var topics: [(pattern: String, glyph: String)] = []
        public init() {}
        public static func == (a: Look, b: Look) -> Bool {
            a.map == b.map && a.colors == b.colors && a.topics.map { $0.pattern + "\u{0}" + $0.glyph } == b.topics.map { $0.pattern + "\u{0}" + $0.glyph }
        }
    }

    public static let palette: [UInt32] = [0xB5543A, 0x5E7F5A, 0x4F6D8A, 0x8A6A3C, 0x7A5C8E, 0x3F7F7A, 0x9A4E6A, 0x6B6B3A, 0x5A6A9A, 0x8A5A4A]

    private static func lastComponent(_ cwd: String) -> String {
        var c = cwd; while c.hasSuffix("/") { c.removeLast() }
        return c.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
    }
    private static func trimmed(_ cwd: String) -> String { var c = cwd; while c.hasSuffix("/") { c.removeLast() }; return c }
    private static func isHome(_ cwd: String) -> Bool {
        let parts = trimmed(cwd).split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0].isEmpty && parts[1] == "home" && !parts[2].isEmpty
    }

    /// "notify-app" -> "NA", "audiobooks" -> "Au", "helm_merge" -> "HM", the home folder -> "~".
    public static func initials(_ cwd: String) -> String {
        let name = lastComponent(cwd)
        if name.isEmpty || isHome(cwd) { return "~" }
        let words = name.split(whereSeparator: { "-_ .".contains($0) }).map(String.init)
        if words.count >= 2 { return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased() }
        let p = String(name.prefix(2))
        return p.prefix(1).uppercased() + p.dropFirst()
    }

    /// The workspace area and project of `cwd` (folders below `workspace/`); nil outside a `workspace/` folder.
    public static func areaOf(_ cwd: String) -> (area: String, project: String?)? {
        let parts = trimmed(cwd).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let i = parts.firstIndex(of: "workspace"), i + 1 < parts.count, !parts[i + 1].isEmpty else { return nil }
        let proj = i + 2 < parts.count ? parts[i + 2] : ""
        return (parts[i + 1], (proj.isEmpty || proj.hasPrefix(".")) ? nil : proj)
    }

    /// The worktree's own folder (`.../.claude/worktrees/musik-drei` -> "musik-drei"), else "".
    public static func worktree(_ cwd: String) -> String {
        let c = trimmed(cwd)
        guard let r = c.range(of: "/.claude/worktrees/") else { return "" }
        return String(c[r.upperBound...].split(separator: "/", omittingEmptySubsequences: true).first ?? "")
    }

    private static func keys(_ cwd: String) -> [String] {
        let c = trimmed(cwd)
        if c.hasPrefix("/tmp") { return ["tmp"] }
        if isHome(c) { return ["~"] }
        guard let (area, project) = areaOf(cwd) else { return [] }
        return [project.map { "\(area)/\($0)" }, project, area].compactMap { $0 }
    }

    /// The configured picture (topic of the title or worktree, then area/project, project, area); nil = the initials.
    public static func glyph(cwd: String, title: String, look: Look) -> String? {
        if !look.topics.isEmpty {
            let text = title + " " + worktree(cwd)
            for t in look.topics {
                if let re = try? NSRegularExpression(pattern: t.pattern, options: [.caseInsensitive]),
                   re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return t.glyph }
            }
        }
        for k in keys(cwd) { if let g = look.map[k] { return g } }
        return nil
    }

    /// Kotlin's `String.hashCode` (UTF-16, wrapping), so a folder gets the same colour as on Android.
    static func javaHash(_ s: String) -> Int32 {
        var h: Int32 = 0
        for u in s.utf16 { h = h &* 31 &+ Int32(u) }
        return h
    }

    /// A stable palette slot: one per workspace area, else per folder.
    public static func slot(_ cwd: String, size: Int) -> Int {
        let key = (areaOf(cwd)?.area ?? trimmed(cwd)).lowercased()
        let m = Int(javaHash(key)) % size
        return m < 0 ? m + size : m
    }

    /// 0xRRGGBB background: the configured colour of area/project, project or area, else a palette colour.
    public static func color(cwd: String, look: Look) -> UInt32 {
        for k in keys(cwd) { if let c = look.colors[k] { return c } }
        return palette[slot(cwd, size: palette.count)]
    }

    /// The three blocks of a hello's `config` (`avatars`, `avatar_colors`, `avatar_topics`); lenient.
    public static func look(from config: JSON) -> Look {
        var l = Look()
        for (k, v) in config["avatars"].object ?? [:] {
            if let g = v.string?.trimmingCharacters(in: .whitespaces), !g.isEmpty, g.count <= 8 { l.map[k] = g }
        }
        for (k, v) in config["avatar_colors"].object ?? [:] {
            if let h = v.string?.trimmingCharacters(in: .whitespaces), h.count == 7, h.hasPrefix("#"), let n = UInt32(h.dropFirst(), radix: 16) { l.colors[k] = n }
        }
        for t in config["avatar_topics"].array {
            if let p = t[0].string, let g = t[1].string?.trimmingCharacters(in: .whitespaces), !g.isEmpty, g.count <= 8 { l.topics.append((p, g)) }
        }
        return l
    }
}
