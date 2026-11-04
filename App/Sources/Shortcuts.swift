import AppIntents

/// "Hey Siri, Jarvis in Relay" or the Action Button: opens Relay straight into Jarvis, listening.
/// (iOS gives third-party apps no always-on wake word; Siri and the Action Button are the hands-free way in.)
struct AskJarvisIntent: AppIntent {
    static var title: LocalizedStringResource = "Jarvis fragen"
    static var description = IntentDescription("Öffnet Relay mit Jarvis und hört sofort zu.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.openJarvis = true
        return .result()
    }
}

struct RelayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskJarvisIntent(),
                    phrases: ["Jarvis in \(.applicationName)",
                              "Frag Jarvis in \(.applicationName)",
                              "\(.applicationName) Jarvis"],
                    shortTitle: "Jarvis fragen",
                    systemImageName: "waveform")
    }
}
