import Foundation

/// Why the link to the PC failed, in terms the user can act on (Martin, 2026-11-10: say why it does not work and
/// offer the fitting help instead of the raw error text).
public enum ConnectProblem: String, Sendable, CaseIterable {
    /// The phone has neither Wi-Fi nor mobile data.
    case noNetwork
    /// The PC is reached through the tailnet and the phone has no tailnet address.
    case tailscaleOff
    /// Only home-network addresses are configured and the phone is neither in a Wi-Fi nor on a VPN.
    case noRoute
    /// The gateway announced that the PC suspends (`desktop_sleep`).
    case pcSleeping
    /// Nothing answers at the PC's address: off, asleep or not in the network.
    case pcUnreachable
    /// The PC answers, but nothing listens on the SSH port.
    case sshDown
    /// The PC's name cannot be resolved.
    case badAddress
    /// SSH answered and refused this phone's key.
    case authRejected
    /// The PC showed another host key than the pinned one.
    case hostKeyChanged
    /// SSH works, but the gateway (notifyd) does not answer.
    case gatewayDown
    /// A link that worked was cut; the app reconnects on its own.
    case interrupted
    case unknown
}

/// What the help row offers for a problem.
public enum ConnectAction: String, Sendable, CaseIterable {
    case tailscaleConnect, tailscaleOpen, phoneSettings, relaySettings, copySetupKey, copyGatewayStart, acceptHostKey

    public var label: String {
        switch self {
        case .tailscaleConnect: return Tailnet.connectButton
        case .tailscaleOpen: return "Tailscale öffnen"
        case .phoneSettings: return "iOS-Einstellungen"
        case .relaySettings: return "Adresse prüfen"
        case .copySetupKey, .copyGatewayStart: return "Befehl kopieren"
        case .acceptHostKey: return "Neuen Schlüssel übernehmen"
        }
    }
}

/// The help for one problem: a short title for the status line, one sentence why, what to do, and buttons.
public struct ConnectHelp: Equatable, Sendable {
    public let problem: ConnectProblem
    public let title: String
    public let text: String
    public let steps: [String]
    public let actions: [ConnectAction]
    /// The raw error, shown small where it helps (unknown errors, the gateway's own words).
    public let detail: String

    /// Nothing to explain (a cut link that reconnects on its own): only the title in the status line.
    public var isEmpty: Bool { text.isEmpty && steps.isEmpty && actions.isEmpty }
}

public enum ConnectDiagnosis {
    /// Where a connect attempt failed: before SSH was up, or in the `serve` channel behind it.
    public enum Stage: String, Sendable { case connect, serve }

    /// What is known when a connect attempt failed.
    public struct Facts: Sendable {
        public var message: String
        public var stage: Stage?
        public var hostKeyChanged: Bool
        /// The link had been up (`hello_ok` seen) before it failed.
        public var wasConnected: Bool
        public var network: Bool
        public var wifi: Bool
        public var vpn: Bool
        public var hosts: [String]
        public var tailnetUp: Bool
        public var pcSleeping: Bool

        public init(message: String, stage: Stage? = nil, hostKeyChanged: Bool = false, wasConnected: Bool = false,
                    network: Bool = true, wifi: Bool = true, vpn: Bool = false, hosts: [String] = [],
                    tailnetUp: Bool = false, pcSleeping: Bool = false) {
            self.message = message; self.stage = stage; self.hostKeyChanged = hostKeyChanged
            self.wasConnected = wasConnected; self.network = network; self.wifi = wifi; self.vpn = vpn
            self.hosts = hosts; self.tailnetUp = tailnetUp; self.pcSleeping = pcSleeping
        }
    }

    public static let gatewayStartCommand = "systemctl --user start notifyd"
    public static let sshStartCommand = "sudo systemctl start sshd"

    /// The reason behind a failed attempt. What the PC itself said (host key, key refused, gateway) counts first, then
    /// what the phone knows about its own network, last the wording of the error.
    public static func problem(_ f: Facts) -> ConnectProblem {
        let m = f.message.lowercased()
        if f.hostKeyChanged { return .hostKeyChanged }
        if !f.network { return .noNetwork }
        if contains(m, ["anmeldung abgelehnt", "authentication", "allauthenticationoptionsfailed"]) { return .authRejected }
        if contains(m, ["daemon is not running"]) { return .gatewayDown }
        if f.pcSleeping { return .pcSleeping }
        if f.stage == .serve { return f.wasConnected ? .interrupted : .gatewayDown }
        if Tailnet.showHint(failed: true, network: f.network, hosts: f.hosts, tailnetUp: f.tailnetUp) { return .tailscaleOff }
        if ConnText.noRoute(hosts: f.hosts, vpn: f.vpn) && !f.wifi { return .noRoute }
        if contains(m, ["connection refused", "connectionrefused", "läuft sshd"]) { return .sshDown }
        if contains(m, ["nodename nor servname", "name or service not known", "dns", "unknown host", "cannot resolve"]) { return .badAddress }
        if contains(m, ["zeitüberschreitung", "timeout", "timed out", "address already in use", "unreachable", "no route",
                        "network is down", "host is down", "connection errors"]) { return .pcUnreachable }
        if f.wasConnected || contains(m, ["already closed", "verbindung getrennt", "connection reset", "broken pipe", "eof"]) { return .interrupted }
        return .unknown
    }

    /// Title, explanation, steps and buttons for a problem. `hosts` decides whether Tailscale is part of the way,
    /// `tailnetUp` whether it is on; `message` is the raw error.
    public static func help(_ p: ConnectProblem, message: String = "", hosts: [String] = [], tailnetUp: Bool = false) -> ConnectHelp {
        let viaTailnet = Tailnet.needsTailnet(hosts: hosts)
        let raw = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        func make(_ title: String, _ text: String, _ steps: [String] = [], _ actions: [ConnectAction] = [], detail: String = "") -> ConnectHelp {
            ConnectHelp(problem: p, title: title, text: text, steps: steps, actions: actions, detail: detail)
        }
        switch p {
        case .noNetwork:
            return make("Kein Netz", "Das iPhone hat weder WLAN noch Mobilfunk.",
                        ["Flugmodus aus? WLAN oder mobile Daten an?", "Sobald wieder Netz da ist, verbindet Relay von selbst."],
                        [.phoneSettings])
        case .tailscaleOff:
            return make(Tailnet.hint, "Der PC ist nur über Tailscale erreichbar, und auf dem iPhone ist Tailscale gerade nicht verbunden (iOS beendet es im Hintergrund manchmal).",
                        ["„\(Tailnet.connectButton)“ startet deinen Kurzbefehl und kehrt hierher zurück."],
                        [.tailscaleConnect, .tailscaleOpen])
        case .noRoute:
            return make("Kein Weg zum PC", "Die eingetragene Adresse gilt nur im heimischen Netz, und das iPhone ist gerade weder im WLAN noch über ein VPN verbunden.",
                        ["Zuhause: WLAN einschalten.", "Unterwegs: Tailscale einrichten und die Tailscale-Adresse des PCs als zweite Adresse eintragen."],
                        [.relaySettings, .tailscaleOpen])
        case .pcSleeping:
            return make("PC schläft", "Der PC hat sich in den Ruhezustand verabschiedet. Relay versucht es alle fünf Minuten wieder.",
                        ["Am PC: eine Taste drücken oder den Einschaltknopf, dann hier „Erneut“."])
        case .pcUnreachable:
            let text = viaTailnet && tailnetUp
                ? "Der PC antwortet nicht. Tailscale ist auf dem iPhone an, also ist der PC vermutlich aus, schläft oder hat selbst kein Netz."
                : "Der PC antwortet nicht. Er ist vermutlich aus, schläft oder hängt nicht im selben Netz."
            var steps = ["Am PC: einschalten oder aufwecken und prüfen, ob er Netz hat."]
            if viaTailnet { steps.append("In der Tailscale-App nachsehen, ob der PC dort als verbunden steht.") }
            return make("PC nicht erreichbar", text, steps, viaTailnet ? [.tailscaleOpen] : [.relaySettings])
        case .sshDown:
            return make("PC nimmt keine Verbindung an", "Der PC ist an, aber der SSH-Dienst antwortet nicht (oder der Port stimmt nicht).",
                        ["Am PC im Terminal: \(sshStartCommand)", "Port in den Relay-Einstellungen prüfen (üblich ist 22)."],
                        [.relaySettings])
        case .badAddress:
            return make("Adresse des PCs nicht gefunden", "Der eingetragene Name lässt sich nicht auflösen.",
                        viaTailnet ? ["Namen aus Tailscale (MagicDNS) gibt es nur, solange Tailscale verbunden ist.", "Sonst die Adresse in den Einstellungen prüfen."]
                                   : ["Adresse in den Einstellungen prüfen (Tippfehler?)."],
                        viaTailnet ? [.relaySettings, .tailscaleOpen] : [.relaySettings])
        case .authRejected:
            return make("PC lehnt dieses iPhone ab", "Der PC kennt den Schlüssel dieses iPhones nicht (oder der Benutzername stimmt nicht).",
                        ["Befehl kopieren und am PC im Terminal ausführen (notifyd setup key …).", "Benutzernamen in den Einstellungen prüfen."],
                        [.copySetupKey, .relaySettings])
        case .hostKeyChanged:
            return make("Host-Schlüssel passt nicht", "Der PC weist sich mit einem anderen Schlüssel aus als beim ersten Verbinden. Relay verbindet aus Sicherheitsgründen nicht.",
                        ["Normal nach einer Neuinstallation des PCs oder neu eingerichtetem SSH: dann den neuen Schlüssel übernehmen.",
                         "Hast du am PC nichts geändert, nicht übernehmen und die Adresse prüfen."],
                        [.acceptHostKey, .relaySettings], detail: raw)
        case .gatewayDown:
            let known = message.lowercased().contains("daemon is not running")
            return make("Gateway läuft nicht", "Der PC ist erreichbar, aber der Relay-Dienst (notifyd) antwortet dort nicht.",
                        ["Am PC im Terminal: \(gatewayStartCommand)", "Läuft er schon, hilft: systemctl --user restart notifyd"],
                        [.copyGatewayStart], detail: known ? "" : raw)
        case .interrupted:
            return make("Verbindung unterbrochen, verbinde neu…", "")
        case .unknown:
            return make("Verbindung klappt nicht", "Relay erreicht den PC nicht, der Grund ist unklar.",
                        ["„Erneut“ versuchen. Bleibt es dabei: Einstellungen → Nutzungsprotokoll → „Fehler melden“."],
                        [.relaySettings], detail: raw)
        }
    }

    private static func contains(_ m: String, _ needles: [String]) -> Bool { needles.contains { m.contains($0) } }
}
