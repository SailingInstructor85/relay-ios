import Foundation

/// Two addresses for the same PC (LAN and a VPN such as Tailscale): the app probes both and connects to the one that
/// answers. The host key is shared, it is the same machine.
public enum HostChoice {
    /// The configured addresses: trimmed, without blanks and doubles, the primary first.
    public static func candidates(_ hosts: [String]) -> [String] {
        var seen: Set<String> = []
        return hosts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The order of attempts: the address that worked last time first, then the configured order.
    public static func order(candidates: [String], lastGood: String) -> [String] {
        let g = lastGood.trimmingCharacters(in: .whitespaces)
        guard !g.isEmpty, candidates.contains(g) else { return candidates }
        return [g] + candidates.filter { $0 != g }
    }

    /// The address to connect to: the first answering probe (`reachable`, in order of their answers), else the one that
    /// worked last time, else the primary. nil without any address.
    public static func pick(candidates: [String], reachable: [String], lastGood: String) -> String? {
        if let r = reachable.first(where: { candidates.contains($0) }) { return r }
        return order(candidates: candidates, lastGood: lastGood).first
    }

    /// Words for the settings: which address the link uses.
    public static func label(active: String, candidates: [String]) -> String {
        guard candidates.count > 1, !active.isEmpty else { return "" }
        return "über \(active)"
    }
}
