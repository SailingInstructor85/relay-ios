import SwiftUI
import RelayCore

/// "Desktop ausschalten ...": shows what a power-off or standby ends (rpc `power_status`), then asks twice.
/// The gateway runs `sudo -n systemctl ...`; if the PC has no rule for it the gateway's error text is shown as is.
struct PowerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("powerDryRun") private var dryRun = true
    @State private var status: PowerStatus?
    @State private var error: String?
    @State private var result: String?
    @State private var working = false
    @State private var ask: Action?

    enum Action: String, Identifiable {
        case off = "power_off", standby = "standby"
        var id: String { rawValue }
        var title: String { self == .off ? "Jetzt ausschalten" : "Jetzt in Standby" }
    }

    var body: some View {
        NavigationStack {
            List {
                if dryRun {
                    Section { Label("Testlauf ist an (Einstellungen). Es wird nichts ausgeschaltet.", systemImage: "testtube.2").font(.callout).foregroundStyle(.orange) }
                }
                if let s = status {
                    Section("Das endet") {
                        Text(s.sessions == 0 ? "Keine Sitzungen offen." : "\(s.sessions) Sitzungen laufen.")
                        ForEach(s.busy) { b in
                            VStack(alignment: .leading) {
                                Text(b.title).lineLimit(1)
                                Text("\(b.alias) · arbeitet gerade").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        if s.tasks > 0 { Text("\(s.tasks) Hintergrundaufgaben laufen.").foregroundStyle(.orange) }
                        if s.uptimeS > 0 { Text("PC läuft seit \(AccountsText.uptime(s.uptimeS)).").font(.caption).foregroundStyle(.secondary) }
                        Text(s.reopen ? "Das Gateway öffnet diese Sitzungen nach dem nächsten Start wieder."
                                      : "Die Sitzungen werden nach dem nächsten Start nicht automatisch geöffnet.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if error == nil {
                    Section { HStack { ProgressView(); Text("Prüfe, was endet ...").foregroundStyle(.secondary) } }
                }
                if let e = error { Section { Text(e).foregroundStyle(.red).font(.callout).textSelection(.enabled) } }
                if let r = result { Section { Label(r, systemImage: "checkmark.circle").foregroundStyle(.green).font(.callout) } }
                Section {
                    Button(role: .destructive) { ask = .off } label: { Label(dryRun ? "Ausschalten (Testlauf)" : "Ausschalten", systemImage: "power") }
                    Button { ask = .standby } label: { Label(dryRun ? "Standby (Testlauf)" : "Standby", systemImage: "moon.zzz") }
                } footer: {
                    Text("Ohne Pi oder Wake-on-LAN startet der PC nicht wieder per Handy. Standby lässt Sitzungen weiterlaufen und braucht den Pi zum Aufwecken.")
                }
                .disabled(working || status == nil)
            }
            .navigationTitle("Desktop ausschalten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Schließen") { dismiss() } } }
            .confirmationDialog(ask == .off ? "Desktop wirklich ausschalten?" : "Desktop in Standby schicken?", isPresented: Binding(get: { ask != nil }, set: { if !$0 { ask = nil } }), titleVisibility: .visible, presenting: ask) { a in
                Button(dryRun ? "\(a.title) (Testlauf)" : a.title, role: .destructive) { Task { await run(a) } }
            } message: { _ in
                Text((status?.busy.isEmpty ?? true) ? "Offene Sitzungen enden." : ((status?.busy.count ?? 0) == 1 ? "1 Sitzung arbeitet gerade und wird unterbrochen." : "\(status?.busy.count ?? 0) Sitzungen arbeiten gerade und werden unterbrochen."))
            }
            .task { await load() }
        }
    }

    private func load() async {
        do { status = PowerStatus.from(try await model.rpc("power_status", [:])); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func run(_ a: Action) async {
        working = true; error = nil; result = nil; defer { working = false }
        do {
            let r = try await model.rpc(a.rawValue, ["confirm": true, "dry_run": .bool(dryRun)], timeout: 30)
            if r.flag("dry_run") { result = "Testlauf: das Gateway hätte \(a == .off ? "ausgeschaltet" : "Standby gestartet"). Der PC bleibt an." }
            else { result = a == .off ? "Das Gateway fährt den PC in wenigen Sekunden herunter." : "Der PC geht in wenigen Sekunden in Standby." }
        } catch { self.error = "Das Gateway meldet: \(error.localizedDescription)" }
    }
}
