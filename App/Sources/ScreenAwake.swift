import SwiftUI
import UIKit
import RelayCore

/// Hält den Bildschirm an, solange ein Chat oder der Live-Bildschirm offen ist und zuletzt vor weniger als 60 s berührt
/// wurde, solange eine Mikrofon-Aufnahme läuft (höchstens 10 Minuten ab ihrem Start) oder solange der Sprachmodus offen
/// ist (`AwakePolicy`). Die Gründe gelten nebeneinander, erst wenn keiner mehr greift, sperrt iOS wieder normal.
/// Berührungen zählt ein Gestenerkenner am Fenster, der nie auslöst und nichts verschluckt.
@MainActor
final class ScreenAwake {
    static let shared = ScreenAwake()
    private var watchers: Set<UUID> = []
    /// Laufende Aufnahmen je `VoiceIO` mit ihrem Start.
    private var recordings: [String: Date] = [:]
    /// Ansichten, die den Bildschirm durchgehend anhalten (Sprachmodus).
    private var pins: Set<UUID> = []
    private var lastTouch = Date()
    private var timer: Task<Void, Never>?
    private var recognizer: TouchWatch?

    func begin(_ id: UUID) {
        watchers.insert(id)
        lastTouch = Date()
        attach()
        apply()
    }

    func end(_ id: UUID) {
        watchers.remove(id)
        if watchers.isEmpty { detach() }
        apply()
    }

    /// Eine Mikrofon-Aufnahme beginnt: Der Bildschirm bleibt an, höchstens `AwakePolicy.recordingLimit` lang.
    func recordingStarted(_ who: String) {
        recordings[who] = Date()
        apply()
    }

    /// Die Aufnahme ist vorbei: Ab sofort gilt wieder die normale Sperre (sofern kein anderer Grund greift).
    func recordingEnded(_ who: String) {
        guard recordings.removeValue(forKey: who) != nil else { return }
        apply()
    }

    func pin(_ id: UUID) {
        pins.insert(id)
        apply()
    }

    func unpin(_ id: UUID) {
        pins.remove(id)
        apply()
    }

    func touched() {
        lastTouch = Date()
        apply()
    }

    private func apply() {
        timer?.cancel(); timer = nil
        let now = Date()
        let since = recordings.values.max()  // die jüngste Aufnahme zählt
        let watching = !watchers.isEmpty, pinned = !pins.isEmpty
        let on = AwakePolicy.keepAwake(watching: watching, lastTouch: lastTouch, recordingSince: since, pinned: pinned, now: now)
        if UIApplication.shared.isIdleTimerDisabled != on { UIApplication.shared.isIdleTimerDisabled = on }
        guard let wait = AwakePolicy.nextCheck(watching: watching, lastTouch: lastTouch, recordingSince: since,
                                               pinned: pinned, now: now) else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.apply()
        }
    }

    private func attach() {
        guard recognizer == nil, let w = window else { return }
        let r = TouchWatch { Task { @MainActor in ScreenAwake.shared.touched() } }
        w.addGestureRecognizer(r)
        recognizer = r
    }

    private func detach() {
        if let r = recognizer { r.view?.removeGestureRecognizer(r) }
        recognizer = nil
    }

    private var window: UIWindow? {
        let all = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return all.first { $0.isKeyWindow } ?? all.first
    }
}

/// Sieht jede Berührung im Fenster und löst nie aus; andere Gesten (Tippen, Scrollen) laufen ungestört weiter.
final class TouchWatch: UIGestureRecognizer {
    private let onTouch: () -> Void

    init(onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { onTouch() }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

private struct KeepAwake: ViewModifier {
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content
            .onAppear { ScreenAwake.shared.begin(id) }
            .onDisappear { ScreenAwake.shared.end(id) }
    }
}

extension View {
    /// Der Bildschirm bleibt an, solange diese Ansicht offen ist und innerhalb der letzten 60 s berührt wurde.
    func keepsScreenAwake() -> some View { modifier(KeepAwake()) }
}
