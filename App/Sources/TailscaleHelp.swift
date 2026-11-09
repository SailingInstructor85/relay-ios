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

/// The hint above the session list: no link, Tailscale probably off, with the connect button.
struct TailscaleHintRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Tailnet.hint, systemImage: "network.slash").font(.footnote)
            HStack(spacing: 10) {
                Button { TailscaleLauncher.connect() } label: { Label(Tailnet.connectButton, systemImage: "bolt.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .accessibilityIdentifier("tailscaleConnect")
                Button("Tailscale öffnen") { TailscaleLauncher.openApp() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Settings → Tailscale: the shortcut's name and how to create it.
struct TailscaleSettingsView: View {
    @AppStorage(TailscaleLauncher.shortcutKey) private var shortcut = Tailnet.defaultShortcut

    var body: some View {
        Form {
            Section {
                Text("iOS beendet Tailscale im Hintergrund manchmal. Erreicht Relay den PC dann nicht, steht über der Sitzungsliste „\(Tailnet.hint)“ mit dem Knopf „\(Tailnet.connectButton)“. Er startet einen Kurzbefehl, der Tailscale verbindet und zu Relay zurückkehrt. Danach verbindet Relay neu.")
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
