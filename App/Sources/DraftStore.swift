import SwiftUI
import UIKit
import RelayCore

/// Entwürfe der Eingabefelder auf dem iPhone (`drafts.json` in Application Support, Regeln in `Drafts` und
/// `DraftBook`, RelayCore). Jede Änderung gilt sofort im Speicher und wird kurz darauf geschrieben
/// (`Drafts.saveDelay`), beim Wechsel in den Hintergrund sofort. So übersteht der Text einen Absturz und das Beenden
/// der App durch iOS.
@MainActor
final class DraftStore {
    static let shared = DraftStore()

    private var book = DraftBook()
    private var dirty = false
    private var pending: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("drafts.json")
    }

    private init() {
        if let u = Self.url, let d = try? Data(contentsOf: u) { book = DraftBook.decode(d) }
        if book.prune(now: Date().timeIntervalSince1970) { dirty = true; write() }
        let leaving = [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                       UIApplication.willTerminateNotification]
        for name in leaving {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DraftStore.shared.flush() }
            })
        }
    }

    func text(_ key: String) -> String { book.text(key) }

    func set(_ key: String, _ text: String) {
        if book.set(key, text, now: Date().timeIntervalSince1970) { changed() }
    }

    func remove(_ key: String) {
        if book.remove(key) { changed() }
    }

    /// Jetzt schreiben, wenn etwas offen ist (die App geht in den Hintergrund).
    func flush() {
        pending?.cancel()
        pending = nil
        write()
    }

    /// Ein Schreibvorgang ist höchstens `Drafts.saveDelay` entfernt; läuft schon einer an, nimmt er diese Änderung mit.
    private func changed() {
        dirty = true
        guard pending == nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Drafts.saveDelay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            self.write()
        }
    }

    private func write() {
        guard dirty, let u = Self.url else { return }
        if book.isEmpty {
            try? FileManager.default.removeItem(at: u)
            dirty = false
        } else if let d = book.encode() {
            do { try d.write(to: u, options: .atomic); dirty = false } catch {
                // bleibt offen und wird mit der nächsten Änderung oder beim Wechsel in den Hintergrund erneut versucht
                AppLog.shared.log("warn", "entwurf", "Entwurf nicht gesichert: \(error.localizedDescription)")
            }
        }
    }
}

/// Hält den Text eines Eingabefelds als Entwurf fest (`DraftStore`): Beim Erscheinen kommt ein gesicherter Entwurf
/// ins leere Feld zurück, jede Änderung wird gesichert, ein geleertes Feld (auch nach dem Senden) löscht ihn.
/// `heard`: was ein laufendes Diktat bis jetzt erkannt hat ("" ohne Diktat); es gehört zum Entwurf, solange es noch
/// nicht im Feld steht. `key` nil: nichts sichern.
private struct DraftKeeper: ViewModifier {
    let key: String?
    @Binding var text: String
    let heard: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard let key, let back = Drafts.restore(field: text, stored: DraftStore.shared.text(key)) else { return }
                text = back
                UsageRecorder.shared.record("entwurf", "wiederhergestellt", kind: Drafts.kind(key), length: back.count)
            }
            .onChange(of: text) { _, t in save(t, heard) }
            .onChange(of: heard) { _, h in save(text, h) }
    }

    @MainActor private func save(_ typed: String, _ heard: String) {
        guard let key else { return }
        DraftStore.shared.set(key, Drafts.combined(typed: typed, heard: heard))
    }
}

extension View {
    /// Sichert den Text eines Eingabefelds als Entwurf unter `key` (`Drafts.jarvis`, `Drafts.session`, …).
    func keepsDraft(_ key: String?, text: Binding<String>, heard: String = "") -> some View {
        modifier(DraftKeeper(key: key, text: text, heard: heard))
    }
}
