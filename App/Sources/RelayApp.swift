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
                .preferredColorScheme(UITestMode.colorScheme) // nur im UI-Testmodus gesetzt, sonst nil (System)
                .onOpenURL { model.receive($0) }
                .onAppear {
                    UsageRecorder.shared.appStarted(); AppHealth.shared.start(); model.start(); Outbox.shared.start(); model.requestNotificationPermission()
                    if let u = UITestMode.shareFile() { model.receive(u) }
                }
                .onChange(of: phase) { _, p in
                    model.setForeground(p == .active)
                    UsageRecorder.shared.phase(p)
                    if p == .active { AppHealth.shared.refresh() }
                    if p == .background {
                        model.questionPromptDue = true  // beim nächsten Öffnen das Blatt „Rückfrage jetzt“ prüfen
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
        AppLog.shared.install()
        return true
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        let info = r.notification.request.content.userInfo
        let tapped = r.actionIdentifier == UNNotificationDefaultActionIdentifier
        if let req = info["request"] as? String {
            switch r.actionIdentifier {
            case "approve": await BackgroundRefresh.withBackgroundTime { await Approvals.shared.fromNotification(request: req, confirm: nil, ok: true) }
            case "deny": await BackgroundRefresh.withBackgroundTime { await Approvals.shared.fromNotification(request: req, confirm: nil, ok: false) }
            default: await MainActor.run { Approvals.shared.showSheet = true }
            }
            return
        }
        if let id = info["confirm"] as? String {
            switch r.actionIdentifier {
            case "approve": await BackgroundRefresh.withBackgroundTime { await Approvals.shared.fromNotification(request: nil, confirm: id, ok: true) }
            case "deny": await BackgroundRefresh.withBackgroundTime { await Approvals.shared.fromNotification(request: nil, confirm: id, ok: false) }
            default: await MainActor.run { Approvals.shared.showSheet = true }
            }
            return
        }
        if info["jarvisSay"] != nil {  // eine Rückmeldung des Chiefs: Sie steht im Jarvis-Chat
            if tapped { await MainActor.run { AppModel.shared.openJarvis = true } }
            return
        }
        if let ref = info["notice"] as? String {
            if r.actionIdentifier == "answer" || r.actionIdentifier == "yes" {
                let typed = (r as? UNTextInputNotificationResponse)?.userText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let text = r.actionIdentifier == "yes" ? "ja" : typed
                await BackgroundRefresh.withBackgroundTime { await AppModel.shared.answerFromNotification(ref: ref, text: text) }
            } else if tapped {
                // die Mitteilung führt schon zur Rückfrage: kein Blatt zusätzlich
                await MainActor.run { AppModel.shared.questionPromptDue = false; AppModel.shared.openNotice = ref }
            }
            return
        }
        if let id = info["locreq"] as? String, tapped {
            let exp = Double(info["locexp"] as? String ?? "") ?? 0
            await MainActor.run { Task { await Locator.shared.fulfil(id: id, expires: exp) } }
            return
        }
        guard let key = info["key"] as? String else { return }
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
    @ObservedObject private var approvals = Approvals.shared
    var body: some View {
        VStack(spacing: 0) {
            if model.configured && !model.locked { TopNotices(); SigningBanner() }
            ZStack {
                if model.configured { RootTabs() } else { NavigationStack { SetupView(firstRun: true) } }
                if model.locked { LockView() }
            }
        }
        .tint(RelayColor.primary)
        .sheet(isPresented: $approvals.showSheet) { ApprovalSheet() }
        // beim Öffnen der App: die älteste offene Rückfrage (Herunterwischen zählt wie „Später“)
        .sheet(isPresented: Binding(get: { model.showQuestionPrompt && !model.locked && model.configured },
                                    set: { if !$0 { model.questionPromptLater() } })) {
            QuestionPromptSheet().environmentObject(model)
        }
        .onChange(of: model.locked) { _, locked in if !locked { model.offerQuestionPrompt() } }
        .sheet(isPresented: Binding(get: { !model.incomingFiles.isEmpty && !model.locked && model.configured },
                                    set: { if !$0 { model.dropIncoming() } })) {
            ShareView(files: model.incomingFiles) { model.dropIncoming() }.environmentObject(model)
        }
    }
}

// MARK: shared bits

extension Session {
    var toolIcon: String {
        switch tool { case "codex": return "chevron.left.forwardslash.chevron.right"; case "agy": return "sparkles"; default: return "asterisk" }
    }
    /// Farbe der Agentenmarke im Chat-Kopf: Claude orange, Codex türkis, Antigravity violett.
    var toolColor: Color {
        switch tool { case "codex": return .teal; case "agy": return .purple; default: return .orange }
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
                let c: Color = stale ? .gray : RelayColor.error
                Circle().strokeBorder(c, lineWidth: 2).frame(width: 14, height: 14)
                    .overlay(Circle().fill(c).frame(width: 6, height: 6))
            case "exited":
                Circle().strokeBorder(Color.gray, lineWidth: 1.5).frame(width: 10, height: 10)
            default:
                Circle().fill(stale ? Color.gray : RelayColor.tertiary).frame(width: 9, height: 9)
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
