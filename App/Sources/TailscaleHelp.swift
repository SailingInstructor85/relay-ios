import SwiftUI
import Darwin
import RelayCore

/// "Tailscale verbinden": runs the user's shortcut with Tailscale's "Connect" action and comes back via `relay://`;
/// without a shortcut name it opens Tailscale (its URL scheme if there is one, else the App Store page).
@MainActor
enum TailscaleLauncher {
    static let shortcutKey = "tailscaleShortcut"

    static var shortcutName: String {
        let n = UserDefaults.standard.string(forKey: shortcutKey) ?? Tailnet.defaultShortcut
        return n.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func connect() {
        UsageRecorder.shared.record("liste", "tailscale verbinden", kind: "knopf")
        if let u = Tailnet.shortcutURL(name: shortcutName) { UIApplication.shared.open(u) } else { openApp() }
    }

    static func openApp() {
        if let app = URL(string: Tailnet.appScheme), UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let store = URL(string: Tailnet.appStore) {
            UIApplication.shared.open(store)
        }
    }

    /// A tailnet address (utun with 100.64.0.0/10 or fd7a:115c:a1e0::/48) on one of the phone's interfaces.
    nonisolated static func tailnetUp() -> Bool { Tailnet.tailnetUp(interfaceAddresses()) }

    nonisolated static func interfaceAddresses() -> [(name: String, address: String)] {
        var list: [(name: String, address: String)] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            defer { p = a.pointee.ifa_next }
            guard let sa = a.pointee.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(sa, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            list.append((name: String(cString: a.pointee.ifa_name), address: String(cString: host)))
        }
        return list
    }
}

/// The help above the session list when the link failed: why (in plain words), what to do, and the fitting buttons
/// (`ConnectDiagnosis` in RelayCore). The title itself stands in the status line above.
struct ConnectHelpRow: View {
    let help: ConnectHelp
    let openSettings: () -> Void
    @State private var confirmKey = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(help.text).font(.footnote).accessibilityIdentifier("connectHelp")
            ForEach(help.steps, id: \.self) { step in
                Text("• " + step).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if !help.detail.isEmpty {
                Text(help.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            if !help.actions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(help.actions.enumerated()), id: \.offset) { i, action in
                        if i == 0 {
                            Button(label(action)) { run(action) }.buttonStyle(.borderedProminent).controlSize(.small)
                                .accessibilityIdentifier(ident(action))
                        } else {
                            Button(label(action)) { run(action) }.buttonStyle(.bordered).controlSize(.small)
                                .accessibilityIdentifier(ident(action))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .confirmationDialog("Neuen Host-Schlüssel übernehmen?", isPresented: $confirmKey, titleVisibility: .visible) {
            Button("Übernehmen und verbinden", role: .destructive) {
                UsageRecorder.shared.record("liste", "host-schlüssel übernommen", kind: "knopf")
                AppModel.shared.forgetHostKey()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Nur, wenn du den PC neu aufgesetzt oder SSH neu eingerichtet hast. Relay merkt sich dann den Schlüssel, den der PC jetzt zeigt.")
        }
    }

    private func label(_ a: ConnectAction) -> String {
        copied && (a == .copySetupKey || a == .copyGatewayStart) ? "Kopiert" : a.label
    }

    /// `tailscaleConnect` is the identifier the Tailscale hint always had.
    private func ident(_ a: ConnectAction) -> String { a == .tailscaleConnect ? "tailscaleConnect" : "connectHelp-" + a.rawValue }

    private func run(_ a: ConnectAction) {
        if a != .tailscaleConnect { UsageRecorder.shared.record("liste", "verbindungshilfe", kind: "knopf", detail: a.rawValue) }
        switch a {
        case .tailscaleConnect: TailscaleLauncher.connect()
        case .tailscaleOpen: TailscaleLauncher.openApp()
        case .phoneSettings:
            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
        case .relaySettings: openSettings()
        case .copySetupKey: UIPasteboard.general.string = AppModel.shared.setupCommand; copied = true
        case .copyGatewayStart: UIPasteboard.general.string = ConnectDiagnosis.gatewayStartCommand; copied = true
        case .acceptHostKey: confirmKey = true
        }
    }
}

/// Settings → Tailscale: the shortcut's name and how to create it.
struct TailscaleSettingsView: View {
    @AppStorage(TailscaleLauncher.shortcutKey) private var shortcut = Tailnet.defaultShortcut

    var body: some View {
        Form {
            Section {
                Text("iOS beendet Tailscale im Hintergrund manchmal. Erreicht Relay den PC dann nicht, steht über der Sitzungsliste „\(Tailnet.hint)“ mit dem Knopf „\(Tailnet.connectButton)“. Er startet einen Kurzbefehl, der Tailscale verbindet und zu Relay zurückkehrt. Danach verbindet Relay neu. Scheitert die Verbindung aus einem anderen Grund (PC aus, Gateway läuft nicht, kein Netz), steht dort stattdessen dieser Grund mit der passenden Hilfe.")
                    .font(.callout)
            }
            Section("Kurzbefehl") {
                TextField(Tailnet.defaultShortcut, text: $shortcut)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("tailscaleShortcutName")
                Text("Name des Kurzbefehls in der Kurzbefehle-App. Leer lassen, dann öffnet der Knopf nur die Tailscale-App.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { TailscaleLauncher.connect() } label: { Label("Jetzt ausprobieren", systemImage: "play.circle") }
            }
            Section("So legst du ihn an") {
                Text("1. Kurzbefehle-App öffnen, oben rechts auf „+“ tippen.")
                Text("2. „Aktion hinzufügen“, nach „Tailscale“ suchen und „Connect“ (Verbinden) wählen. Das gibt es ab Tailscale 1.36.")
                Text("3. Den Kurzbefehl „\(shortcut.isEmpty ? Tailnet.defaultShortcut : shortcut)“ nennen, genau wie oben.")
                Text("4. Hier „Jetzt ausprobieren“ tippen. iOS fragt beim ersten Mal, ob Relay Kurzbefehle starten darf.")
            }.font(.callout)
        }
        .navigationTitle("Tailscale")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { UsageRecorder.shared.screen("tailscale") }
    }
}
