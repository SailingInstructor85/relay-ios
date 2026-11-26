import SwiftUI
import UserNotifications
import RelayCore

/// Signatur und Update (2026-11-26): wann die eigene Signatur abläuft und ob in der SideStore-Quelle eine neuere
/// Version liegt. Das Ablaufdatum steht in `embedded.mobileprovision` im App-Bundle (RelayCore `Provisioning`).
/// Fehlt die Datei (Simulator, CI), bleibt alles leer und die App zeigt nichts.
/// Ab drei Tagen Rest steht ein Hinweis oben in der App, dazu lokale Mitteilungen 72, 48 und 24 Stunden vor Ablauf
/// (bei jedem Start und jedem Öffnen neu geplant). Das Datum geht einmal je Start ins Nutzungsprotokoll, damit der PC
/// warnen kann. Die Quelle wird höchstens alle sechs Stunden geladen. Ohne Netz oder bei einem Fehler bleibt die App still.
@MainActor
final class AppHealth: ObservableObject {
    static let shared = AppHealth()
    private static let lastCheckKey = "updateLastCheck"
    private static let latestKey = "updateLatest"

    /// Ablauf der Signatur, nil ohne Profil im Bundle.
    @Published private(set) var expiry: Date?
    /// Neuere Version aus der Quelle, nil wenn die App aktuell ist oder noch nichts bekannt ist.
    @Published private(set) var update: String?
    /// Meldung, wenn sich SideStore nicht öffnen ließ.
    @Published var storeNote: String?

    private var started = false
    private var checking = false

    private init() {}

    static var ownVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    func status(now: Date = Date()) -> SigningStatus? { expiry.map { SigningStatus(expiry: $0, now: now) } }

    /// Etwas zu zeigen: Ablaufdatum bekannt oder Update da.
    var hasInfo: Bool { expiry != nil || update != nil }

    /// Beim Start der App.
    func start() {
        guard !started else { return }
        started = true
        expiry = Self.readExpiry()
        if let st = status() {
            UsageRecorder.shared.record("app", "signatur", detail: st.usageDetail)
        } else if !UITestMode.active {
            UsageRecorder.shared.record("app", "signatur", detail: "kein Ablaufdatum: embedded.mobileprovision fehlt oder ist nicht lesbar")
        }
        if UITestMode.active {
            update = AppUpdate.available(latest: UITestMode.updateVersion, own: Self.ownVersion)
        } else {
            update = AppUpdate.available(latest: UserDefaults.standard.string(forKey: Self.latestKey), own: Self.ownVersion)
        }
        refresh()
    }

    /// Bei jedem Öffnen der App: Mitteilungen neu planen, Quelle prüfen, wenn es wieder Zeit ist.
    func refresh() {
        guard started else { return }
        scheduleReminders()
        Task { await checkUpdate() }
    }

    private static func readExpiry() -> Date? {
        if UITestMode.active {
            // künstliches Ablaufdatum für die UI-Tests (RELAY_UI_SIGN_DAYS), sonst wie ohne Profil
            return UITestMode.signDays.map { Date().addingTimeInterval($0 * 86400) }
        }
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return Provisioning.expiration(in: data)
    }

    // MARK: Mitteilungen

    private func scheduleReminders() {
        guard !UITestMode.active else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: SigningReminders.ids)
        guard let expiry else { return }
        let now = Date()
        for item in SigningReminders.plan(expiry: expiry, now: now) {
            let c = UNMutableNotificationContent()
            c.title = SigningReminders.title
            c.body = item.body
            c.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.fire.timeIntervalSince(now)), repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: c, trigger: trigger))
        }
    }

    // MARK: Update

    private func checkUpdate() async {
        guard !UITestMode.active, !checking else { return }
        let d = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        guard AppUpdate.due(last: d.object(forKey: Self.lastCheckKey) as? Double, now: now) else { return }
        guard let url = URL(string: AppUpdate.sourceURL) else { return }
        checking = true
        defer { checking = false }
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        // Kein Netz, Fehler oder unlesbare Antwort: still bleiben, beim nächsten Öffnen wieder versuchen.
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let source = JSON.parse(data),
              let latest = AppUpdate.latestVersion(in: source) else { return }
        d.set(now, forKey: Self.lastCheckKey)
        d.set(latest, forKey: Self.latestKey)
        let found = AppUpdate.available(latest: latest, own: Self.ownVersion)
        if found != update {
            update = found
            if let found { UsageRecorder.shared.record("app", "update verfügbar", detail: found) }
        }
    }

    func openStore() {
        UsageRecorder.shared.record("app", "sidestore öffnen")
        guard let url = URL(string: AppUpdate.storeURL) else { return }
        storeNote = nil
        UIApplication.shared.open(url, options: [:]) { ok in
            guard !ok else { return }
            Task { @MainActor in AppHealth.shared.storeNote = AppUpdate.storeFailed }
        }
    }
}

/// Hinweis oben in der App, sobald die Signatur in höchstens drei Tagen abläuft.
struct SigningBanner: View {
    @ObservedObject private var health = AppHealth.shared

    var body: some View {
        // Ohne Ablaufdatum (Simulator, CI) entsteht kein Element.
        if health.expiry != nil {
            // Die Restzeit zählt weiter, auch wenn sonst nichts neu gezeichnet wird.
            TimelineView(.periodic(from: .now, by: 300)) { ctx in
                if let st = health.status(now: ctx.date), st.warn { banner(st) }
            }
        }
    }

    private func banner(_ st: SigningStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                Text(st.bannerTitle() + " " + SigningStatus.wifiHint).font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("signBanner")
                Spacer(minLength: 0)
            }
            HStack {
                Button(AppUpdate.storeLabel) { health.openStore() }.font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("signBannerStore")
                if let note = health.storeNote { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
}

/// Abschnitt in den Einstellungen, direkt unter „Status“. Erscheint nur, wenn es etwas zu zeigen gibt.
struct AppHealthSection: View {
    @ObservedObject private var health = AppHealth.shared

    var body: some View {
        if health.hasInfo {
            Section {
                if let st = health.status() {
                    Text(st.line()).accessibilityIdentifier("signLine")
                }
                if let v = health.update {
                    Text(AppUpdate.title(v)).accessibilityIdentifier("updateLine")
                }
                Button { health.openStore() } label: { Label(AppUpdate.storeLabel, systemImage: "arrow.up.forward.app") }
                    .accessibilityIdentifier("settingsStore")
                if let note = health.storeNote { Text(note).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("App und Signatur")
            } footer: {
                Text("Mit kostenloser Apple-ID gilt die Signatur sieben Tage, danach startet Relay nicht mehr. Erneuern und Aktualisieren gehen in SideStore nur, wenn das iPhone in einem WLAN ist (irgendeines, nicht nur das Heimnetz) und LocalDevVPN läuft. Über Mobilfunk geht es nicht. Relay erinnert dich 72, 48 und 24 Stunden vor Ablauf.")
            }
        }
    }
}

/// Karte oben im Tab „Mehr“, wenn in der SideStore-Quelle eine neuere Version liegt.
struct UpdateCard: View {
    @ObservedObject private var health = AppHealth.shared

    var body: some View {
        if let v = health.update {
            VStack(alignment: .leading, spacing: 4) {
                MoreGroup {
                    MoreRow(title: AppUpdate.title(v), symbol: "arrow.down.circle", detail: AppUpdate.storeLabel) { health.openStore() }
                        .accessibilityIdentifier("updateRow")
                }
                Text(health.storeNote ?? AppUpdate.hint).font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant)
                    .padding(.horizontal, RelaySpace.rowOuter + 12)
                    .accessibilityIdentifier("updateHint")
            }
            .padding(.top, 8)
        }
    }
}
