import SwiftUI
import RelayCore

/// Connection settings and the phone's public key (pairing: `notifyd setup key "<key>"` on the Desktop).
struct SetupView: View {
    @EnvironmentObject var model: AppModel
    var firstRun = false
    @State private var host = ""
    @State private var host2 = ""
    @State private var port = "22"
    @State private var user = ""
    @State private var copied = ""
    @AppStorage("vaultDir") private var vaultDir = VaultDrop.defaultDir

    var body: some View {
        Form {
            if firstRun {
                Section {
                    Text("Relay verbindet dein iPhone per SSH mit dem Relay-Gateway (notifyd) auf deinem Linux-Desktop – im LAN oder über WireGuard.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("1 · Schlüssel auf dem Desktop eintragen") {
                Text("Führe auf dem Desktop aus:").font(.footnote)
                Text(model.setupCommand).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button { UIPasteboard.general.string = model.setupCommand; flash("Befehl kopiert") } label: { Label("Befehl kopieren", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless) // sonst löst ein Tipp in der Zeile beide Knöpfe aus
                    Spacer()
                    ShareLink(item: model.setupCommand) { Label("Teilen", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderless)
                }
                Button { UIPasteboard.general.string = model.publicKey; flash("Schlüssel kopiert") } label: { Label("Nur öffentlichen Schlüssel kopieren", systemImage: "key") }
                if !copied.isEmpty { Text(copied).font(.caption).foregroundStyle(.green) }
                Text("Der Schlüssel darf auf dem Desktop nur `notifyd ssh-entry` ausführen – keine Shell.").font(.caption).foregroundStyle(.secondary)
            }
            Section("2 · Desktop") {
                TextField("Host (z. B. 192.168.1.20 oder 10.0.0.1)", text: $host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Zweite Adresse (optional, z. B. Tailscale)", text: $host2)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Text("Beide Adressen gehören zum selben PC (gleicher Host-Schlüssel). Die App prüft kurz, welche erreichbar ist, und nimmt die.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Port", text: $port).keyboardType(.numberPad)
                TextField("Benutzer", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(firstRun ? "Verbinden" : "Speichern & neu verbinden") {
                    model.host = host.trimmingCharacters(in: .whitespaces)
                    model.host2 = host2.trimmingCharacters(in: .whitespaces)
                    model.port = Int(port) ?? 22
                    model.user = user.trimmingCharacters(in: .whitespaces)
                    model.reconnect()
                }.disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || user.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section("Status") {
                HStack { Text("Verbindung"); Spacer(); Text(model.connLabel).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                if !via.isEmpty { HStack { Text("Adresse"); Spacer(); Text(via).foregroundStyle(.secondary) } }
                if !model.hostKey.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gepinnter Host-Schlüssel")
                        Text(HostKeys.fingerprint(model.hostKey)).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Button("Host-Schlüssel vergessen (neu pinnen)", role: .destructive) { model.forgetHostKey() }
                }
            }
            if !firstRun {
                NotifySettingsSection()
                ChatSettingsSection()
                SpeechSettingsSection()
                AgentSettingsSection()
                Section("Profil") {
                    NavigationLink { ProfileView() } label: { Label("Persönliche Angaben", systemImage: "person.text.rectangle") }
                    Text("Name, Adresse, E-Mail für Formulare, gespeichert auf dem Desktop (profile.json).").font(.caption).foregroundStyle(.secondary)
                }
                Section("Ablage") {
                    TextField(VaultDrop.defaultDir, text: $vaultDir).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Vault-Ordner auf dem PC für „Ins Vault einsortieren“ beim Teilen einer Datei. Ein Agent legt sie dort in „\(VaultDrop.inbox)“ ab und sortiert sie ein.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Sicherheit") {
                    Toggle("Mit Face ID sperren", isOn: $model.lockEnabled)
                    Text("Relay sperrt sich, sobald die App in den Hintergrund geht.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Info") {
                    Text(AppModel.appVersion).font(.caption).foregroundStyle(.secondary)
                    Link("Relay auf GitHub", destination: URL(string: "https://github.com/chart21/relay")!)
                }
            }
        }
        .navigationTitle(firstRun ? "Relay einrichten" : "Einstellungen")
        .onAppear { host = model.host; host2 = model.host2; port = String(model.port); user = model.user }
    }

    /// "über 100.73.162.18": which of two addresses the link uses.
    private var via: String {
        model.state == .connected ? HostChoice.label(active: model.activeHost, candidates: model.hosts) : ""
    }

    private func flash(_ s: String) {
        copied = s
        Task { try? await Task.sleep(nanoseconds: 2_000_000_000); copied = "" }
    }
}
