import Foundation

/// RAM and CPU of the Desktop (rpc `memory`, `summary: true`).
public struct MemoryInfo: Sendable, Hashable {
    public let totalMb: Double, availableMb: Double, swapTotalMb: Double, swapUsedMb: Double
    public let cpuPct: Double?
    public var usedMb: Double { max(0, totalMb - availableMb) }

    public init(totalMb: Double, availableMb: Double, swapTotalMb: Double = 0, swapUsedMb: Double = 0, cpuPct: Double? = nil) {
        self.totalMb = totalMb; self.availableMb = availableMb; self.swapTotalMb = swapTotalMb; self.swapUsedMb = swapUsedMb
        self.cpuPct = cpuPct
    }

    public static func from(_ o: JSON) -> MemoryInfo? {
        guard o.has("total_mb") else { return nil }
        return MemoryInfo(totalMb: o.num("total_mb"), availableMb: o.num("available_mb"), swapTotalMb: o.num("swap_total_mb"),
                          swapUsedMb: o.num("swap_used_mb"), cpuPct: o["cpu_pct"].double)
    }
}

/// What waits for the user across sessions: the overview's status strip and "Weiter" in a chat. Port of Triage.kt.
public enum Triage {
    /// Sessions that want the user, in the order to visit them: questions first (the longest wait first), then unread
    /// ones (newest first). Never `current`; ended sessions only when unread.
    public static func queue(_ live: [Session], unread: Set<String>, current: String? = nil) -> [Session] {
        let open = live.filter { s in current.map { !s.matches($0) } ?? true }
        let waiting = open.filter { $0.waits }.sorted { $0.lastActivity < $1.lastActivity }
        let rest = open.filter { !$0.waits && unread.contains($0.key) }.sorted { $0.lastActivity > $1.lastActivity }
        return waiting + rest
    }

    public static func next(_ live: [Session], unread: Set<String>, current: String? = nil) -> Session? {
        queue(live, unread: unread, current: current).first
    }

    public struct Counts: Sendable, Equatable { public let need: Int, unread: Int }

    public static func counts(_ live: [Session], unread: Set<String>) -> Counts {
        Counts(need: live.filter { $0.waits }.count, unread: live.filter { !$0.waits && unread.contains($0.key) }.count)
    }

    /// "2 brauchen dich" or, when nobody waits, "3 ungelesen"; "" when there is nothing to say.
    public static func shortCount(_ c: Counts) -> String {
        if c.need > 0 { return c.need == 1 ? "1 braucht dich" : "\(c.need) brauchen dich" }
        if c.unread > 0 { return "\(c.unread) ungelesen" }
        return ""
    }

    /// Usage level for colours: 0 ok, 1 high (from 70 %), 2 nearly out (from 90 %).
    public static func level(_ pct: Double) -> Int { pct >= 90 ? 2 : (pct >= 70 ? 1 : 0) }

    /// One pill per account with a usage window: alias, 5-hour use and weekly use ("" when unknown).
    public struct Quota: Sendable, Equatable, Identifiable {
        public var id: String { alias }
        public let alias: String, text: String, level: Int, week: String, weekLevel: Int
    }

    public static func quota(_ usage: [UsageAccount]) -> [Quota] {
        usage.filter { $0.error.isEmpty && !$0.gone && !$0.windows.isEmpty }.sorted { $0.alias < $1.alias }.map { u in
            let h5 = u.windows.first { $0.name != "week" }
            let wk = u.windows.first { $0.name == "week" }
            return Quota(alias: u.alias, text: h5.map { "\(Int($0.pct))%" } ?? "-", level: h5.map { level($0.pct) } ?? 0,
                         week: wk.map { "\(Int($0.pct))%" } ?? "", weekLevel: wk.map { level($0.pct) } ?? 0)
        }
    }

    /// "10.4G" in use; level 1 from 80 %, 2 from 90 %.
    public struct Ram: Sendable, Equatable { public let text: String, level: Int }

    public static func ram(_ m: MemoryInfo?) -> Ram? {
        guard let m, m.totalMb > 0 else { return nil }
        let pct = m.usedMb / m.totalMb * 100
        return Ram(text: String(format: "%.1fG", m.usedMb / 1024), level: pct >= 90 ? 2 : (pct >= 80 ? 1 : 0))
    }

    /// "CPU 63%"; level 1 from 80 %, 2 from 95 %.
    public struct Cpu: Sendable, Equatable { public let text: String, level: Int }

    public static func cpu(_ m: MemoryInfo?) -> Cpu? {
        guard let p = m?.cpuPct else { return nil }
        return Cpu(text: "CPU \(Int(p.rounded()))%", level: p >= 95 ? 2 : (p >= 80 ? 1 : 0))
    }

    /// "Stand vor 5 Min." for the offline list; "" when never synced.
    public static func staleText(lastSync: Double, now: Date = Date()) -> String {
        guard lastSync > 0 else { return "" }
        let d = max(0, now.timeIntervalSince1970 - lastSync)
        if d < 60 { return "Stand von gerade eben" }
        if d < 3600 { return "Stand vor \(Int(d / 60)) Min." }
        if d < 86400 { return "Stand vor \(Int(d / 3600)) Std." }
        return "Stand vor \(Int(d / 86400)) T."
    }

    /// Whether a `hello_ok` session counts as read: its `seen_at` is not older than its last activity.
    public static func seenAfterActivity(_ s: Session) -> Bool { s.seenAt > 0 && s.seenAt >= s.lastActivity }
}
