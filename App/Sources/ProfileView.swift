import SwiftUI
import RelayCore

/// The profile kept on the Desktop (`~/.config/notifyd/profile.json`, rpc `profile_get` / `profile_set`): edit, copy per field.
/// No card or account numbers: the gateway refuses them.
struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @State private var fields: [String: String] = [:]
    @State private var emails = ""
    @State private var loaded = false
    @State private var updatedAt: Double?
    @State private var busy = false
    @State private var error: String?
    @State private var info: String?

    var body: some View {
        Form {
            if model.state != .connected {
                Section { Text("Das Profil liegt auf dem Desktop. Verbinde dich zuerst.").foregroundStyle(.secondary) }
            }
            Section("Angaben") {
                ForEach(ProfileFields.all, id: \.key) { f in
                    HStack {
                        TextField(f.label, text: Binding(get: { fields[f.key] ?? "" }, set: { fields[f.key] = $0 }))
                            .autocorrectionDisabled()
                        copyButton(fields[f.key] ?? "")
                    }
                }
                HStack {
                    TextField("E-Mail-Adressen (mit Komma getrennt)", text: $emails)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    copyButton(emails)
                }
            }
            Section {
                Button(busy ? "Speichere…" : "Auf dem Desktop speichern") { Task { await save() } }
                    .disabled(busy || !loaded || model.state != .connected)
                if let u = updatedAt, u > 0 {
                    Text("Zuletzt geändert: \(Date(timeIntervalSince1970: u).formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let i = info { Text(i).font(.footnote).foregroundStyle(.green) }
                if let e = error { Text(e).font(.footnote).foregroundStyle(.red) }
            } footer: {
                Text("Keine Karten- oder IBAN-Nummern: der Desktop weist sie ab.")
            }
        }
        .navigationTitle("Profil")
        .task { await load() }
    }

    private func copyButton(_ v: String) -> some View {
        Button { UIPasteboard.general.string = v } label: { Image(systemName: "doc.on.doc") }
            .buttonStyle(.borderless).disabled(v.isEmpty).accessibilityLabel("Kopieren")
    }

    private func apply(_ r: JSON) {
        let v = ProfileFields.values(r["profile"])
        fields = v.fields
        emails = v.emails.joined(separator: ", ")
        updatedAt = r["updated_at"].double
        loaded = true
    }

    private func load() async {
        guard model.state == .connected else { return }
        do { apply(try await model.rpc("profile_get", timeout: 15)); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func save() async {
        if let bad = fields.first(where: { ProfileFields.looksSensitive($0.value) }) {
            let label = ProfileFields.all.first { $0.key == bad.key }?.label ?? bad.key
            error = "„\(label)“ sieht wie eine Karten- oder IBAN-Nummer aus. Die wird nicht gespeichert."
            return
        }
        busy = true; info = nil; error = nil
        defer { busy = false }
        let p = ProfileFields.make(fields: fields, emails: ProfileFields.splitEmails(emails))
        do {
            let r = try await model.rpc("profile_set", ["profile": p, "edited_at": .number(Date().timeIntervalSince1970)], timeout: 15)
            apply(r)
            if r.flag("conflict") { info = "Auf dem Desktop war das Profil neuer. Es wurde nichts überschrieben, das gespeicherte steht jetzt hier." }
            else { info = "Gespeichert." }
        } catch { self.error = error.localizedDescription }
    }
}
