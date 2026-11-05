import SwiftUI
import RelayCore

/// Settings section "Jarvis-Agent": account, model and effort of the overview agent (rpc `get_config` / `set_config`),
/// plus the dry-run switch for desktop power.
struct AgentSettingsSection: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("powerDryRun") private var dryRun = true
    @State private var current: OverviewConfig?
    @State private var draft = OverviewConfig()
    @State private var error: String?
    @State private var saving = false
    @State private var saved = false

    private var changed: Bool { current.map { !draft.diff(from: $0).isEmpty } ?? false }

    var body: some View {
        Section("Jarvis-Agent") {
            if model.state != .connected && current == nil {
                Text("Nur verbunden einstellbar.").font(.caption).foregroundStyle(.secondary)
            } else if current == nil && error == nil {
                HStack { ProgressView(); Text("Lade ...").foregroundStyle(.secondary) }
            }
            if current != nil {
                Picker("Konto", selection: $draft.alias) {
                    ForEach(aliases, id: \.alias) { Text("\($0.label) (\($0.alias))").tag($0.alias) }
                }
                Picker("Modell", selection: $draft.model) {
                    ForEach(modelChoices, id: \.self) { Text($0.isEmpty ? "CLI-Standard" : $0).tag($0) }
                }
                TextField("Modell (Freitext)", text: $draft.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(.callout, design: .monospaced))
                Picker("Effort", selection: $draft.effort) {
                    ForEach(effortChoices, id: \.self) { Text($0.isEmpty ? "CLI-Standard" : ($0 == "low" ? "low (Standard)" : $0)).tag($0) }
                }
                Button(saving ? "Speichere ..." : "Speichern") { Task { await save() } }.disabled(!changed || saving)
                if saved { Text("Gespeichert.").font(.caption).foregroundStyle(.green) }
            }
            if let e = error { Text(e).font(.caption).foregroundStyle(.red) }
            Text("Der Agent, der Jarvis antwortet. Niedriger Effort hält ihn schnell und billig.").font(.caption).foregroundStyle(.secondary)
        }
        .task(id: model.state == .connected) { if model.state == .connected { await load() } }

        Section("Desktop ausschalten") {
            Toggle("Testlauf", isOn: $dryRun)
            Text(dryRun ? "An: „Ausschalten“ und „Standby“ prüfen nur (dry_run), der PC bleibt an. Zum echten Ausschalten den Testlauf abschalten."
                        : "Aus: „Ausschalten“ und „Standby“ wirken wirklich. Der PC braucht dafür eine sudo-Regel (`sudo -n systemctl poweroff` bzw. `suspend`). Ohne Pi oder Wake-on-LAN startet er nicht wieder per Handy.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var aliases: [Account] {
        var l = model.accounts
        if !draft.alias.isEmpty, !l.contains(where: { $0.alias == draft.alias }) {
            l.append(Account(alias: draft.alias, tool: "", label: draft.alias, home: "", loggedIn: true))
        }
        return l
    }
    private var modelChoices: [String] {
        let base = [""] + OverviewConfig.models
        return base.contains(draft.model) ? base : base + [draft.model]
    }
    private var effortChoices: [String] {
        let base = OverviewConfig.efforts + [""]
        return base.contains(draft.effort) ? base : base + [draft.effort]
    }

    private func load() async {
        do {
            let c = OverviewConfig.from(try await model.rpc("get_config", [:]))
            current = c; draft = c; error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let cur = current else { return }
        saving = true; saved = false; defer { saving = false }
        do {
            let c = OverviewConfig.from(try await model.rpc("set_config", .object(draft.diff(from: cur))))
            current = c; draft = c; error = nil; saved = true
        } catch { self.error = error.localizedDescription }
    }
}
