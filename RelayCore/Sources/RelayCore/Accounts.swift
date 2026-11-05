import Foundation

/// Texts for the usage page, the RAM page and desktop power. Pure, so they can be tested.
public enum AccountsText {
    /// The gateway has no `claude-pool` helper: Claude windows are missing, Codex still works.
    public static func isHelperMissing(_ error: String) -> Bool {
        error.lowercased().hasPrefix("usage helper unavailable")
    }

    public static let helperHint = "Die Claude-Limits brauchen den Pool-Helfer `claude-pool` auf dem PC. Er ist dort nicht eingerichtet. Codex-Konten zeigen trotzdem ihre Werte."

    /// Error text for an account: a clear hint for the missing helper, otherwise the gateway's text.
    public static func errorText(_ error: String) -> String { isHelperMissing(error) ? helperHint : error }

    /// "Reicht bis zum Reset, ca. 30 % bleiben ungenutzt" / "leer um 14:05"; "" without a forecast.
    public static func forecast(_ w: UsageWindow, clock: (Double) -> String) -> String {
        if let r = w.runsOutAt { return "leer um \(clock(r))" }
        if let u = w.unusedAtReset { return "Reicht bis zum Reset, ca. \(Int(u.rounded())) % bleiben ungenutzt" }
        return ""
    }

    public static func money(_ v: Double, _ currency: String) -> String {
        let n = String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
        switch currency.uppercased() {
        case "USD", "$": return "\(n) $"
        case "EUR", "€": return "\(n) €"
        case "": return n
        default: return "\(n) \(currency)"
        }
    }

    /// Readable reason a closed session went to sleep (rpc `memory` -> `closed[]`).
    public static func closedReason(_ reason: String, idleH: Double?) -> String {
        let idle = idleH.map { $0 >= 1 ? "idle \(Int($0.rounded())) h" : "idle" } ?? "idle"
        switch reason {
        case "user": return "von dir geschlossen"
        case "idle": return idle
        case "pressure": return idleH != nil ? "\(idle), RAM knapp" : "RAM knapp"
        case "rotate": return "ersetzt (Rotation)"
        case "cancelled": return "abgebrochen"
        default: return reason
        }
    }

    /// "251 MB + 100 MB Swap".
    public static func memory(mb: Double, swapMb: Double) -> String {
        let m = mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : "\(Int(mb)) MB"
        return swapMb >= 1 ? "\(m) + \(Int(swapMb)) MB Swap" : m
    }

    /// Bar fill relative to the biggest entry (0...1).
    public static func relative(_ v: Double, max m: Double) -> Double { m <= 0 ? 0 : Swift.min(1, Swift.max(0, v / m)) }

    /// 1234 -> "1,2k", 2_500_000 -> "2,5M".
    public static func tokens(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if v >= 1_000 { return String(format: "%.1fk", v / 1_000).replacingOccurrences(of: ".", with: ",") }
        return "\(Int(v))"
    }

    public static func cloudState(_ s: String) -> String {
        switch s {
        case "waiting": return "Wartet auf dich"
        case "running": return "Läuft"
        case "ready": return "Bereit"
        case "done": return "Fertig"
        default: return s
        }
    }

    public static func uptime(_ s: Double) -> String {
        let m = Int(s / 60)
        if m < 60 { return "\(m) Min." }
        let h = m / 60
        return h < 48 ? "\(h) Std. \(m % 60) Min." : "\(h / 24) Tage"
    }
}

/// `power_status` (what a power-off or standby would end).
public struct PowerStatus: Sendable, Equatable {
    public struct Busy: Sendable, Equatable, Identifiable { public var id: String { key }; public let key: String, title: String, alias: String }
    public let sessions: Int, tasks: Int, uptimeS: Double, reopen: Bool
    public let busy: [Busy]

    public static func from(_ o: JSON) -> PowerStatus {
        PowerStatus(sessions: o["sessions"].int ?? 0, tasks: o["tasks"].int ?? 0, uptimeS: o.num("uptime_s"), reopen: o.flag("reopen"),
                    busy: o["busy"].array.map { Busy(key: $0.str("key"), title: $0.str("title", $0.str("key")), alias: $0.str("alias")) })
    }
}

/// `get_config` / `set_config`: the Jarvis (overview) agent.
public struct OverviewConfig: Sendable, Equatable {
    public var alias: String, model: String, effort: String, pollFallbackS: Double
    public init(alias: String = "", model: String = "", effort: String = "low", pollFallbackS: Double = 0) {
        self.alias = alias; self.model = model; self.effort = effort; self.pollFallbackS = pollFallbackS
    }
    public static let models = ["haiku", "sonnet", "opus"]
    public static let efforts = ["low", "medium", "high", "xhigh", "max"]

    public static func from(_ o: JSON) -> OverviewConfig {
        let v = o["overview"]
        return OverviewConfig(alias: v.str("alias"), model: v.str("model"), effort: v.str("effort"), pollFallbackS: o.num("poll_fallback_s"))
    }

    /// Only the fields that differ from `old`.
    public func diff(from old: OverviewConfig) -> [String: JSON] {
        var p: [String: JSON] = [:]
        if alias != old.alias { p["overview_alias"] = .string(alias) }
        if model != old.model { p["overview_model"] = .string(model) }
        if effort != old.effort { p["overview_effort"] = .string(effort) }
        return p
    }
}
