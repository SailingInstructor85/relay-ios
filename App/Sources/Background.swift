import SwiftUI
import UIKit
import BackgroundTasks
import LocalAuthentication

/// iOS background app refresh: now and then (iOS decides when, typically every 15 to 60 minutes and less often for
/// apps that are rarely opened) Relay connects briefly, lets the missed events raise their notifications and
/// disconnects again.
enum BackgroundRefresh {
    static let id = "dev.relay.ios.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                let ok = await AppModel.shared.backgroundCheck()
                task.setTaskCompleted(success: ok)
            }
            task.expirationHandler = {
                work.cancel()
                Task { @MainActor in AppModel.shared.releaseBackground() }
            }
        }
    }

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    /// Asks iOS for extra seconds while `body` runs (a reply from a notification in the background).
    @MainActor
    static func withBackgroundTime(_ body: @MainActor () async -> Void) async {
        let box = TaskBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: "relay-action") {
            if box.id != .invalid { UIApplication.shared.endBackgroundTask(box.id); box.id = .invalid }
        }
        await body()
        if box.id != .invalid { UIApplication.shared.endBackgroundTask(box.id); box.id = .invalid }
    }

    private final class TaskBox: @unchecked Sendable { var id: UIBackgroundTaskIdentifier = .invalid }
}

/// Covers the app until Face ID (or the device passcode) unlocks it. On when Settings → "Mit Face ID sperren" is set;
/// locks whenever the app goes to the background.
struct LockView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @State private var autoTried = false
    @State private var prompting = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Relay ist gesperrt").font(.headline)
                Button { Task { await unlock() } } label: { Label("Entsperren", systemImage: "faceid") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .task { if phase == .active { autoUnlock() } }
        .onChange(of: phase) { _, p in
            if p == .background { autoTried = false }
            if p == .active { autoUnlock() }
        }
    }

    private func autoUnlock() {
        guard !autoTried else { return }
        autoTried = true
        Task { await unlock() }
    }

    private func unlock() async {
        guard !prompting else { return }
        prompting = true; defer { prompting = false }
        let ctx = LAContext()
        var err: NSError?
        // without a passcode on the device there is nothing to check against: don't lock the user out
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { model.locked = false; return }
        if (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Relay entsperren")) == true {
            model.locked = false
        }
    }
}
