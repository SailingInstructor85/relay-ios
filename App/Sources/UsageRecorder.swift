import Foundation
import SwiftUI
import RelayCore

/// Nutzungsprotokoll (2026-11-07): was Martin in der App tut, dazu App-Zustände und Fehler, damit ein Agent einen
/// gemeldeten Fehler nachvollziehen und nachstellen kann. Ohne Inhalte, nur Art und Länge (RelayCore `UsageEvent`).
/// Gepuffert in Application Support (`usage-log.json`, 30 Tage), übertragen per `usage_put` ans eigene Gateway,
/// sobald die Verbindung steht. Text der letzten 10 Minuten nur im Speicher, er geht nur bei „Fehler melden“ mit Haken
/// „Inhalte mitsenden“ mit.
@MainActor
final class UsageRecorder: ObservableObject {
    static let shared = UsageRecorder()
    static let enabledKey = "usageLogEnabled"
    private static let runningKey = "usageLogRunning"

    @Published private(set) var pendingCount = 0
    @Published private(set) var total = 0
    @Published private(set) var lastSent: Date?

    private var buffer = UsageBuffer()
    private var contents = RecentContent()
    private var saveTask: Task<Void, Never>?
    private var flushing = false
    private var flushTimer: Task<Void, Never>?
    private var started = false

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            objectWillChange.send()
        }
    }

    private init() {
        if let u = Self.url, let d = try? Data(contentsOf: u), let b = try? JSONDecoder().decode(UsageBuffer.self, from: d) {
            buffer = b
        }
        buffer.prune(now: Date().timeIntervalSince1970)
        publish()
    }

    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("usage-log.json")
    }

    private static var version: String { AppModel.appVersion }

    // MARK: aufzeichnen

    /// Ein Ereignis. `kind`/`length` beschreiben Inhalte, ohne sie zu speichern.
    func record(_ screen: String, _ action: String, session: String? = nil, kind: String? = nil, length: Int? = nil,
                detail: String? = nil, error: String? = nil) {
        guard enabled else { return }
        buffer.append(UsageEvent(ts: Date().timeIntervalSince1970, screen: screen, action: action, session: session,
                                 appVersion: Self.version, kind: kind, length: length, detail: detail, error: error))
        publish()
        scheduleSave()
        if buffer.pendingCount >= 50 { Task { await flush() } }
    }

    /// Text, den Martin gesendet oder diktiert hat: als Ereignis nur Art und Länge, der Text selbst bleibt 10 Minuten
    /// im Speicher für „Fehler melden“ mit Haken.
    func content(_ screen: String, _ action: String, session: String?, kind: String, text: String) {
        guard enabled else { return }
        record(screen, action, session: session, kind: kind, length: text.count)
        contents.add(ts: Date().timeIntervalSince1970, screen: screen, session: session, kind: kind, text: text)
    }

    func screen(_ name: String, session: String? = nil) { record(name, "geöffnet", session: session) }

    // MARK: App-Zustand

    /// Beim Start: War der letzte Lauf noch als aktiv markiert, ist die App vermutlich abgestürzt oder wurde beendet,
    /// während sie im Vordergrund war.
    func appStarted() {
        guard !started else { return }
        started = true
        let wasRunning = UserDefaults.standard.bool(forKey: Self.runningKey)
        record("app", "gestartet", detail: wasRunning ? "letzter Lauf nicht sauber beendet (Absturz?)" : nil)
        UserDefaults.standard.set(true, forKey: Self.runningKey)
        startTimer()
    }

    func phase(_ p: ScenePhase) {
        switch p {
        case .active:
            UserDefaults.standard.set(true, forKey: Self.runningKey)
            record("app", "aktiv")
        case .background:
            UserDefaults.standard.set(false, forKey: Self.runningKey)
            record("app", "hintergrund")
            saveNow()
        default: break
        }
    }

    // MARK: übertragen

    /// Sendet alles Ungesendete in Paketen. Bricht die Verbindung ab, bleiben die Ereignisse für den nächsten Versuch.
    @discardableResult
    func flush() async -> String {
        guard !flushing else { return "Übertragung läuft schon" }
        guard AppModel.shared.state == .connected else { return "Nicht verbunden, wird später gesendet" }
        flushing = true
        defer { flushing = false }
        var sent = 0
        while true {
            let batch = buffer.pending()
            if batch.isEmpty { break }
            do {
                _ = try await AppModel.shared.rpc("usage_put", UsageBuffer.putParams(batch), timeout: 15)
            } catch {
                publish(); saveNow()
                return sent == 0 ? "Nicht gesendet: \(error.localizedDescription)" : "\(sent) gesendet, Rest später"
            }
            buffer.markSent(batch.map(\.id))
            sent += batch.count
        }
        lastSent = Date()
        publish(); saveNow()
        return sent == 0 ? "Nichts Neues zu senden" : "\(sent) Ereignisse gesendet"
    }

    private func startTimer() {
        flushTimer?.cancel()
        flushTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, self.enabled, self.buffer.pendingCount > 0 else { continue }
                await self.flush()
            }
        }
    }

    /// „Fehler melden“: Beschreibung, die Ereignisse der letzten 10 Minuten, mit Haken auch die Inhalte.
    func report(_ text: String, withContents: Bool) async -> Result<String, Error> {
        record("einstellungen", "fehler gemeldet", length: text.count, detail: withContents ? "mit Inhalten" : "ohne Inhalte")
        let now = Date().timeIntervalSince1970
        contents.prune(now: now)
        let p = UsageReport.params(text: text, buffer: buffer, contents: withContents ? contents : nil,
                                   appVersion: Self.version, now: now)
        do {
            let r = try await AppModel.shared.rpc("usage_report", p, timeout: 20)
            await flush()
            return .success(r.str("path"))
        } catch {
            return .failure(error)
        }
    }

    func clear() {
        buffer.clear()
        contents.clear()
        publish(); saveNow()
    }

    // MARK: speichern

    private func publish() {
        pendingCount = buffer.pendingCount
        total = buffer.events.count
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        buffer.prune(now: Date().timeIntervalSince1970)
        guard let u = Self.url, let d = try? JSONEncoder().encode(buffer) else { return }
        try? d.write(to: u, options: .atomic)
    }
}

/// Einstellungsabschnitt „Nutzungsprotokoll“: an/aus, jetzt senden, löschen, Fehler melden.
struct UsageSettingsSection: View {
    @ObservedObject private var rec = UsageRecorder.shared
    @State private var info = ""
    @State private var reporting = false
    @State private var confirmClear = false

    var body: some View {
        Section {
            Toggle("Nutzung aufzeichnen", isOn: Binding(get: { rec.enabled }, set: { rec.enabled = $0 }))
                .accessibilityIdentifier("usageToggle")
            Button { reporting = true } label: { Label(UsageReport.sendLabel, systemImage: "ladybug") }
                .accessibilityIdentifier("usageReport")
            Button { Task { info = await rec.flush() } } label: { Label("Protokoll jetzt senden", systemImage: "arrow.up.doc") }
                .accessibilityIdentifier("usageSend")
            Button(role: .destructive) { confirmClear = true } label: { Label("Protokoll löschen", systemImage: "trash") }
                .accessibilityIdentifier("usageClear")
            if !info.isEmpty { Text(info).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("usageInfo") }
        } header: {
            Text("Nutzungsprotokoll")
        } footer: {
            Text("Zeichnet auf, was du in der App tust (Ansicht, Aktion, Sitzung, Fehler), ohne Inhalte: von Text, Diktat und Fotos nur Art und Länge. Geht nur an dein Gateway, bleibt 30 Tage. \(rec.total) Ereignisse, \(rec.pendingCount) noch nicht gesendet.")
        }
        .confirmationDialog("Protokoll auf dem iPhone löschen?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { rec.clear(); info = "Protokoll gelöscht" }
        } message: {
            Text("Was schon beim Gateway ist, bleibt dort.")
        }
        .sheet(isPresented: $reporting) { ReportBugView { info = $0 } }
    }
}

/// „Fehler melden“: kurze Beschreibung, Haken „Inhalte mitsenden“ (aus), geht als Backlog-Vorschlag ans Gateway.
struct ReportBugView: View {
    var done: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var withContents = false
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Was ist passiert?", text: $text, axis: .vertical).lineLimit(3...8)
                        .accessibilityIdentifier("reportText")
                } footer: {
                    Text("Mit dabei: die Ereignisse der letzten 10 Minuten (ohne Inhalte) und die App-Version.")
                }
                Section {
                    Toggle(UsageReport.contentsLabel, isOn: $withContents).accessibilityIdentifier("reportContents")
                } footer: {
                    Text("Schickt zusätzlich den Text mit, den du in den letzten 10 Minuten gesendet oder diktiert hast. Fotos nie, nur ihr Pfad.")
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle(UsageReport.sendLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sende…" : "Senden") {
                        Task {
                            sending = true
                            defer { sending = false }
                            switch await UsageRecorder.shared.report(text, withContents: withContents) {
                            case .success: done("Fehlermeldung gesendet"); dismiss()
                            case .failure(let e): error = "Nicht gesendet: \(e.localizedDescription)"
                            }
                        }
                    }
                    .disabled(sending || !UsageReport.canSend(text))
                    .accessibilityIdentifier("reportSend")
                }
            }
        }
    }
}
