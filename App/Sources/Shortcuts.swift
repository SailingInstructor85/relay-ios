import AppIntents
import UIKit
import RelayCore

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

/// A session as a Shortcuts parameter (running ones first; the list comes from the last known overview).
struct SessionEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sitzung"
    static var defaultQuery = SessionEntityQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct SessionEntityQuery: EntityQuery {
    @MainActor private func all() -> [SessionEntity] {
        let m = AppModel.shared
        let live = ShareLogic.targets(Array(m.sessions.values), lastKey: m.lastOpenedKey, query: "")
        return live.map { SessionEntity(id: $0.key, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [SessionEntity] {
        await MainActor.run {
            let m = AppModel.shared
            return identifiers.compactMap { id in m.session(for: id).map { SessionEntity(id: $0.key, name: $0.name) } }
        }
    }
    func suggestedEntities() async throws -> [SessionEntity] { await MainActor.run { all() } }
}

struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let text: String
    var localizedStringResource: LocalizedStringResource { "\(text)" }
}

/// What the two shortcuts below need: a link to the Desktop, also from the background (one short connection).
@MainActor
enum IntentLink {
    static func open() async throws -> AppModel {
        let m = AppModel.shared
        guard m.configured else { throw IntentFailure(text: "Relay ist noch nicht eingerichtet.") }
        if UIApplication.shared.applicationState != .active { m.setForeground(false) } else { m.start() }
        guard await m.connectOnce(timeout: 20) else { throw IntentFailure(text: "Keine Verbindung zum Desktop (\(m.connLabel)).") }
        return m
    }
}

/// "Nachricht an Sitzung senden": runs without opening the app. The key sits in the keychain "after first unlock", so it
/// works from the background; the shortcut itself asks for device authentication.
struct SendToSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Nachricht an Sitzung senden"
    static var description = IntentDescription("Schickt einen Text an eine laufende Sitzung auf dem Desktop.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Sitzung") var session: SessionEntity
    @Parameter(title: "Text") var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw IntentFailure(text: "Der Text ist leer.") }
        let m = try await IntentLink.open()
        defer { m.releaseBackground() }
        guard let s = m.session(for: session.id) else { throw IntentFailure(text: "Die Sitzung gibt es nicht mehr.") }
        do { try await m.send(s, text: body) }
        catch let e as RelayError where e.remote && OutboxLogic.isBusyRefusal(e.message) {
            throw IntentFailure(text: "\(s.name) arbeitet gerade. Nichts gesendet.")
        }
        catch { throw IntentFailure(text: "Nicht gesendet: \(error.localizedDescription)") }
        m.markRead(s.key)
        return .result(dialog: "Gesendet an \(s.name).")
    }
}

/// "Neue Sitzung starten": account alias (or auto), folder on the Desktop (`~/projekt` or absolute), first message.
struct StartSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Neue Sitzung starten"
    static var description = IntentDescription("Startet eine neue Agent-Sitzung auf dem Desktop.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Konto (Alias oder auto)", default: "auto") var account: String
    @Parameter(title: "Ordner auf dem Desktop") var folder: String
    @Parameter(title: "Erste Nachricht") var prompt: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dir = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else { throw IntentFailure(text: "Der Ordner fehlt.") }
        let m = try await IntentLink.open()
        defer { m.releaseBackground() }
        let alias = account.trimmingCharacters(in: .whitespaces).isEmpty ? "auto" : account.trimmingCharacters(in: .whitespaces)
        do { _ = try await m.launch(alias: alias, cwd: dir, prompt: prompt, name: nil) }
        catch { throw IntentFailure(text: "Nicht gestartet: \(error.localizedDescription)") }
        m.lastAlias = alias
        return .result(dialog: "Sitzung in \(dir) gestartet.")
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
        AppShortcut(intent: SendToSessionIntent(),
                    phrases: ["Nachricht senden in \(.applicationName)", "\(.applicationName) Nachricht senden"],
                    shortTitle: "Nachricht senden",
                    systemImageName: "paperplane")
        AppShortcut(intent: StartSessionIntent(),
                    phrases: ["Neue Sitzung in \(.applicationName)", "\(.applicationName) neue Sitzung"],
                    shortTitle: "Neue Sitzung",
                    systemImageName: "plus.circle")
    }
}
