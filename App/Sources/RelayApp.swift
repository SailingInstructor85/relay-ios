import SwiftUI
import UserNotifications
import RelayCore

@main
struct RelayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onAppear { model.start(); model.requestNotificationPermission() }
                .onChange(of: phase) { _, p in model.setForeground(p == .active) }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ app: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        if let key = r.notification.request.content.userInfo["key"] as? String {
            await MainActor.run { AppModel.shared.openChat = key }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if model.configured { SessionsView() } else { NavigationStack { SetupView(firstRun: true) } }
    }
}

// MARK: shared bits

extension Session {
    var toolIcon: String {
        switch tool { case "codex": return "chevron.left.forwardslash.chevron.right"; case "agy": return "sparkles"; default: return "asterisk" }
    }
}

struct StateBadge: View {
    let state: String
    var body: some View {
        let (text, color): (String, Color) = {
            switch state {
            case "busy": return ("arbeitet", .blue)
            case "needs_input": return ("wartet", .orange)
            case "exited": return ("beendet", .gray)
            default: return ("bereit", .green)
            }
        }()
        Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule()).foregroundStyle(color)
    }
}

struct ErrorBanner: View {
    @Binding var text: String?
    var body: some View {
        if let t = text {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(t).font(.footnote)
                Spacer()
                Button { text = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            .padding(10).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
        }
    }
}
