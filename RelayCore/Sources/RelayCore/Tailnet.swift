import Foundation

/// Help when Tailscale is off (iOS ends it in the background now and then): Relay can't switch on another app's VPN,
/// but it can run the user's shortcut with Tailscale's "Connect" action (Tailscale 1.36 or newer) and come back via
/// `relay://`. The hint shows only when the PC is reached through the tailnet, the link failed and no tailnet address is
/// on the phone; with Tailscale on and only the gateway silent it stays away.
public enum Tailnet {
    public static let defaultShortcut = "Tailscale verbinden"
    public static let hint = "Keine Verbindung. Tailscale ist vermutlich aus."
    public static let connectButton = "Tailscale verbinden"
    /// Tailscale in the App Store (its "Öffnen" also starts the installed app).
    public static let appStore = "https://apps.apple.com/app/tailscale/id1470499037"
    public static let appScheme = "tailscale://"
    /// The shortcut returns here (`x-success`, `x-cancel`) or with an error (`x-error`).
    public static let callbackDone = "relay://tailscale-verbunden"
    public static let callbackError = "relay://tailscale-fehler"

    /// 100.64.0.0/10 (CGNAT range Tailscale hands out).
    public static func isTailnetIPv4(_ s: String) -> Bool {
        let p = s.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard p.count == 4, p.allSatisfy({ $0 != nil && (0...255).contains($0!) }) else { return false }
        return p[0] == 100 && (64...127).contains(p[1]!)
    }

    /// Tailscale's IPv6 range fd7a:115c:a1e0::/48.
    public static func isTailnetIPv6(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("fd7a:115c:a1e0:")
    }

    /// An address of the PC that needs Tailscale: a tailnet IP, a MagicDNS name (`*.ts.net`) or a bare host name
    /// without dots (MagicDNS short name).
    public static func isTailnetHost(_ host: String) -> Bool {
        let h = host.trimmingCharacters(in: .whitespaces).lowercased()
        guard !h.isEmpty else { return false }
        if isTailnetIPv4(h) || isTailnetIPv6(h) { return true }
        if h.hasSuffix(".ts.net") || h.hasSuffix(".ts.net.") { return true }
        return !h.contains(".") && !h.contains(":") && h != "localhost"
    }

    public static func needsTailnet(hosts: [String]) -> Bool { hosts.contains(where: isTailnetHost) }

    /// Show "Keine Verbindung. Tailscale ist vermutlich aus." with the connect button?
    /// - failed: the last connect attempt failed (`state == .error`), not merely connecting.
    /// - network: the phone has a network at all (without one Tailscale wouldn't help).
    /// - tailnetUp: a tailnet address is on one of the phone's interfaces (utun with 100.x): then the PC or the
    ///   gateway is off, not Tailscale.
    public static func showHint(failed: Bool, network: Bool, hosts: [String], tailnetUp: Bool) -> Bool {
        failed && network && !tailnetUp && needsTailnet(hosts: hosts)
    }

    /// Any of the phone's interface addresses (name, address) from the tailnet.
    public static func tailnetUp(_ addresses: [(name: String, address: String)]) -> Bool {
        addresses.contains { a in
            (a.name.hasPrefix("utun") || a.name.hasPrefix("tun")) && (isTailnetIPv4(a.address) || isTailnetIPv6(a.address))
        }
    }

    /// `shortcuts://x-callback-url/run-shortcut?name=…&x-success=relay://…`: runs the shortcut and returns to Relay.
    public static func shortcutURL(name: String) -> URL? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        let q = [("name", n), ("x-success", callbackDone), ("x-cancel", callbackDone), ("x-error", callbackError)]
            .map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: "shortcuts://x-callback-url/run-shortcut?" + q)
    }

    /// What a `relay://` link from the shortcut means.
    public enum Callback: Equatable { case connected, failed(String) }

    public static func callback(_ url: URL) -> Callback? {
        guard url.scheme?.lowercased() == "relay" else { return nil }
        switch url.host?.lowercased() {
        case "tailscale-verbunden": return .connected
        case "tailscale-fehler":
            let msg = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "errorMessage" })?.value ?? ""
            return .failed(msg)
        default: return nil
        }
    }

    /// Text when the shortcut failed (not created yet, renamed, Tailscale too old).
    public static func failureText(shortcut: String, message: String) -> String {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "Der Kurzbefehl „\(shortcut)“ hat nicht geklappt. Gibt es ihn in der Kurzbefehle-App? Anleitung: Einstellungen → Tailscale."
        return m.isEmpty ? base : base + " (" + m + ")"
    }

    private static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
