import SwiftUI
import RelayCore

/// Connection settings and the phone's public key (pairing: `notifyd setup key "<key>"` on the Desktop).
struct SetupView: View {
    @EnvironmentObject var model: AppModel
    var firstRun = false
    @State private var host = ""
    @State private var port = "22"
    @State private var user = ""
    @State private var copied = ""

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
                    Spacer()
                    ShareLink(item: model.setupCommand) { Label("Teilen", systemImage: "square.and.arrow.up") }
                }
                Button { UIPasteboard.general.string = model.publicKey; flash("Schlüssel kopiert") } label: { Label("Nur öffentlichen Schlüssel kopieren", systemImage: "key") }
                if !copied.isEmpty { Text(copied).font(.caption).foregroundStyle(.green) }
                Text("Der Schlüssel darf auf dem Desktop nur `notifyd ssh-entry` ausführen – keine Shell.").font(.caption).foregroundStyle(.secondary)
            }
            Section("2 · Desktop") {
                TextField("Host (z. B. 192.168.1.20 oder 10.0.0.1)", text: $host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Port", text: $port).keyboardType(.numberPad)
                TextField("Benutzer", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(firstRun ? "Verbinden" : "Speichern & neu verbinden") {
                    model.host = host.trimmingCharacters(in: .whitespaces)
                    model.port = Int(port) ?? 22
                    model.user = user.trimmingCharacters(in: .whitespaces)
                    model.reconnect()
                }.disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || user.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section("Status") {
                HStack { Text("Verbindung"); Spacer(); Text(model.state.label).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                if !model.hostKey.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gepinnter Host-Schlüssel")
                        Text(HostKeys.fingerprint(model.hostKey)).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Button("Host-Schlüssel vergessen (neu pinnen)", role: .destructive) { model.forgetHostKey() }
                }
            }
            if !firstRun {
                Section("Benachrichtigungen") {
                    Toggle("Benachrichtigen bei „fertig“ / „wartet“", isOn: $model.notifyEnabled)
                    Text("iOS hält keine Verbindung im Hintergrund offen. Benachrichtigungen kommen, solange die App offen ist oder kurz im Hintergrund läuft; beim Öffnen zeigt Relay eine Zusammenfassung des Verpassten.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Info") {
                    Text(AppModel.appVersion).font(.caption).foregroundStyle(.secondary)
                    Link("Relay auf GitHub", destination: URL(string: "https://github.com/chart21/relay")!)
                }
            }
        }
        .navigationTitle(firstRun ? "Relay einrichten" : "Einstellungen")
        .onAppear { host = model.host; port = String(model.port); user = model.user }
    }

    private func flash(_ s: String) {
        copied = s
        Task { try? await Task.sleep(nanoseconds: 2_000_000_000); copied = "" }
    }
}
