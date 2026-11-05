import SwiftUI
import RelayCore

/// Settings of the chat composer, read from UserDefaults (the views use the same keys through `@AppStorage`).
enum ChatPrefs {
    static func slashKey(_ tool: String) -> String { "slash.\(tool)" }

    static func slash(_ tool: String) -> [String] {
        let raw = UserDefaults.standard.string(forKey: slashKey(tool)) ?? SlashChips.defaults[tool] ?? ""
        return SlashChips.parse(raw)
    }

    static var quickReplies: [String] {
        QuickReplies.parse(UserDefaults.standard.string(forKey: "quickReplies") ?? QuickReplies.standard)
    }

    static var cleanDictation: Bool { UserDefaults.standard.bool(forKey: "cleanDictation") }
}

/// Settings section "Sitzungen": slash chips per tool, quick replies, dictation clean-up.
struct ChatSettingsSection: View {
    @AppStorage("slash.claude") private var claude = SlashChips.defaults["claude"] ?? ""
    @AppStorage("slash.codex") private var codex = SlashChips.defaults["codex"] ?? ""
    @AppStorage("slash.agy") private var agy = SlashChips.defaults["agy"] ?? ""
    @AppStorage("quickReplies") private var quick = QuickReplies.standard
    @AppStorage("cleanDictation") private var clean = false

    var body: some View {
        Section("Sitzungen") {
            field("Claude", $claude, SlashChips.defaults["claude"] ?? "")
            field("Codex", $codex, SlashChips.defaults["codex"] ?? "")
            field("Antigravity", $agy, SlashChips.defaults["agy"] ?? "")
            Text("Slash-Befehle über dem Eingabefeld, durch Leerzeichen getrennt.").font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Schnellantworten").font(.footnote).foregroundStyle(.secondary)
                TextField(QuickReplies.standard, text: $quick).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Text("Durch | getrennt, höchstens 8. Ein Tipp sendet sofort. Die erste erscheint auch als Aktion an der „fertig“-Mitteilung.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Diktat aufräumen", isOn: $clean)
            Text("Der Desktop korrigiert Verhörer und streicht Füllwörter (kostet Sonnet-Token). Bei Fehler oder Wartezeit bleibt der Rohtext.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Sitzungs-Einstellungen zurücksetzen") {
                claude = SlashChips.defaults["claude"] ?? ""; codex = SlashChips.defaults["codex"] ?? ""; agy = SlashChips.defaults["agy"] ?? ""
                quick = QuickReplies.standard; clean = false
            }
        }
        .onChange(of: quick) { _, _ in AppModel.registerNotificationActions() }
    }

    private func field(_ title: String, _ text: Binding<String>, _ placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.system(.callout, design: .monospaced))
        }
    }
}
