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
                .onAppear { model.start(); Outbox.shared.start(); model.requestNotificationPermission() }
                .onChange(of: phase) { _, p in
                    model.setForeground(p == .active)
                    if p == .background {
                        BackgroundRefresh.schedule()
                        if model.lockEnabled { model.locked = true }
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ app: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AppModel.registerNotificationActions()
        BackgroundRefresh.register()
        return true
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        guard let key = r.notification.request.content.userInfo["key"] as? String else { return }
        switch r.actionIdentifier {
        case "reply":
            let text = (r as? UNTextInputNotificationResponse)?.userText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }
            await BackgroundRefresh.withBackgroundTime { await AppModel.shared.replyFromNotification(key: key, text: text) }
        case "quick":
            await BackgroundRefresh.withBackgroundTime { await AppModel.shared.quickFromNotification(key: key) }
        case "done":
            await BackgroundRefresh.withBackgroundTime { await AppModel.shared.doneFromNotification(key: key) }
        case "mute":
            await MainActor.run { AppModel.shared.toggleMute(key) }
        default:
            await MainActor.run { AppModel.shared.openChat = key }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ZStack {
            if model.configured { SessionsView() } else { NavigationStack { SetupView(firstRun: true) } }
            if model.locked { LockView() }
        }
    }
}

// MARK: shared bits

extension Session {
    var toolIcon: String {
        switch tool { case "codex": return "chevron.left.forwardslash.chevron.right"; case "agy": return "sparkles"; default: return "asterisk" }
    }
}

/// The state of a session as a small shape: spinner (busy), red ring with dot (waits), green dot (ready), hollow ring (ended).
/// `stale` (offline list): all grey, no spinner.
struct StateDot: View {
    let state: String
    var stale = false

    private var word: String {
        let w: String
        switch state {
        case "busy": w = "arbeitet"
        case "needs_input": w = "wartet"
        case "exited": w = "beendet"
        default: w = "bereit"
        }
        return stale ? "\(w), zuletzt bekannt" : w
    }

    var body: some View {
        Group {
            switch state {
            case "busy":
                if stale { Circle().fill(Color.gray).frame(width: 9, height: 9) }
                else { ProgressView().controlSize(.mini).tint(.accentColor) }
            case "needs_input":
                let c: Color = stale ? .gray : .red
                Circle().strokeBorder(c, lineWidth: 2).frame(width: 14, height: 14)
                    .overlay(Circle().fill(c).frame(width: 6, height: 6))
            case "exited":
                Circle().strokeBorder(Color.gray, lineWidth: 1.5).frame(width: 10, height: 10)
            default:
                Circle().fill(stale ? Color.gray : Color.green).frame(width: 9, height: 9)
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word)
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
