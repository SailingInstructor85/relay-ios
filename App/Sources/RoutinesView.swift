import SwiftUI
import Combine
import RelayCore

/// Die Routinen des Gateways (rpc `routines`): einmal geladen für die Ansicht und die App-Suche, das Ereignis
/// `routine_run` hält den letzten Lauf aktuell. Ohne `team:`-Block antwortet das Gateway `enabled: false`.
@MainActor
final class RoutinesStore: ObservableObject {
    static let shared = RoutinesStore()
    @Published private(set) var info = RoutinesInfo.off
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    func refresh(_ model: AppModel) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            info = RoutinesInfo.from(try await model.rpc("routines", [:], timeout: 40))
            error = nil
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Schalter an oder aus (`routine_set`); die Antwort des Gateways ersetzt die Routine. Fehlertext oder nil.
    func set(_ r: Routine, enabled: Bool, model: AppModel) async -> String? {
        do {
            let res = try await model.rpc("routine_set", ["id": .string(r.id), "enabled": .bool(enabled)], timeout: 30)
            info = info.applying(set: r.id, enabled: enabled, result: res)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// „Jetzt ausführen“ (`routine_run`), die Antwort als Satz; der gemeldete Lauf wird zum letzten Lauf.
    func run(_ r: Routine, model: AppModel) async throws -> String {
        let res = try await model.rpc("routine_run", ["id": .string(r.id)], timeout: 90)
        if let run = RoutineRun.from(res["run"]) {
            info = info.applying(runEvent: ["id": .string(r.id), "at": .number(run.at), "ok": run.ok.map { JSON.bool($0) } ?? .null,
                                            "summary": .string(run.summary), "handoff": run.handoff.map { JSON.string($0) } ?? .null])
        }
        return RoutinesText.runResult(res)
    }

    func onRunEvent(_ ev: JSON) { info = info.applying(runEvent: ev) }

    /// Die Sitzung eines Handoffs (`handoffs {state: all}` → `key`), für „Sitzung öffnen“ am letzten Lauf.
    func sessionKey(handoff id: String, model: AppModel) async -> String? {
        let res = try? await model.rpc("handoffs", ["state": .string("all"), "since_h": .number(24 * 30)], timeout: 30)
        return res?["handoffs"].array.first { $0.str("id") == id }?["key"].string
    }
}

/// Liste aller Routinen nach Besitzer, Schalter je Routine, „Neue Routine…“ an den Chef, darunter die systemd-Timer
/// des Benutzers (nur Anzeige). Nachbau des Android-Reiters „Routines“.
struct RoutinesView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var store = RoutinesStore.shared
    @State private var newRoutine = false
    @State private var info: String?
    @State private var now = Date().timeIntervalSince1970

    var body: some View {
        List {
            if let e = store.error { Section { Text(e).font(.footnote).foregroundStyle(.red) } }
            if store.loaded && !store.info.enabled {
                Section {
                    ContentUnavailableView(RoutinesText.disabledTitle, systemImage: "calendar.badge.exclamationmark", description: Text(RoutinesText.disabledText))
                }
            } else if store.info.enabled {
                ForEach(store.info.byOwner) { group in
                    Section(RoutinesLabels.owner(group.owner)) {
                        ForEach(group.routines) { r in RoutineRowView(r: r, now: now) { on in Task { await toggle(r, on) } } }
                    }
                }
                if store.info.routines.isEmpty { Section { Text("Noch keine Routinen.").foregroundStyle(.secondary) } }
                Section {
                    Button { newRoutine = true } label: { Label("Neue Routine…", systemImage: "plus") }.accessibilityIdentifier("routineNew")
                    if let info { Text(info).font(.footnote).foregroundStyle(.secondary) }
                }
                if !store.info.system.isEmpty {
                    Section("System (systemd-Timer, nur Anzeige)") {
                        ForEach(store.info.system) { t in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.subheadline.weight(.medium))
                                if !t.description.isEmpty { Text(t.description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                Text(RoutinesText.timerLine(t, now: now)).font(.caption2).foregroundStyle(t.failed ? Color.red : Color.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Routinen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await store.refresh(model) } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.loading).accessibilityLabel("Aktualisieren")
            }
        }
        .refreshable { await store.refresh(model) }
        .overlay { if store.loading && !store.loaded { ProgressView() } }
        .task { now = Date().timeIntervalSince1970; await store.refresh(model) }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { d in now = d.timeIntervalSince1970 }
        .sheet(isPresented: $newRoutine) {
            NewRoutineSheet { text in await sendNew(text) }.environmentObject(model)
        }
    }

    private func toggle(_ r: Routine, _ on: Bool) async {
        if let e = await store.set(r, enabled: on, model: model) { info = "Nicht geändert: \(e)" } else { info = nil }
    }

    /// „Neue Routine“: in Worten an den Chef (`team_send`), der den Eintrag schreibt und bestätigen lässt.
    private func sendNew(_ text: String) async -> String? {
        do {
            let r = try await model.rpc("team_send", ["to": .string(RoutinesText.chief), "text": .string(RoutinesText.newRoutineRequest(text))], timeout: 60)
            if r.has("enabled"), !r.flag("enabled") { return RoutinesText.disabledTitle }
            info = "An den Chef geschickt" + (r.flag("started") ? " (neue Sitzung gestartet)" : "") + ". Er schreibt den Eintrag und fragt zurück."
            return nil
        } catch {
            return "Nicht gesendet: \(error.localizedDescription)"
        }
    }
}

/// Deutsche Bezeichnungen für Besitzer, Art und Zustellung.
enum RoutinesLabels {
    static func owner(_ id: String) -> String { id == RoutinesText.chief ? "Chef" : id }
    static func kind(_ k: String) -> String {
        switch k {
        case "builtin": return "eingebaut"
        case "prompt": return "Anweisung an den Agenten"
        case "system": return "systemd-Timer"
        default: return k
        }
    }
    static func deliver(_ d: String) -> String {
        switch d {
        case "interrupt": return "sofort melden"
        case "checkin": return "beim Check-in"
        case "log": return "nur protokollieren"
        default: return d
        }
    }
}

/// Eine Zeile: Titel, Beschreibung, Zeitplan, letzter Lauf; der Schalter rechts, der Rest öffnet die Details.
struct RoutineRowView: View {
    let r: Routine
    let now: Double
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink { RoutineDetailView(id: r.id) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.title).font(.body.weight(.medium)).foregroundStyle(r.enabled || r.isSystem ? Color.primary : Color.secondary).lineLimit(2)
                    if !r.description.isEmpty { Text(r.description).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
                    Text(RoutinesText.schedule(r, now: now)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    RunChip(r: r, now: now)
                }
            }
            if !r.isSystem {
                Toggle("", isOn: Binding(get: { r.enabled }, set: { onToggle($0) })).labelsHidden()
                    .accessibilityLabel("\(r.title) aktiv")
            }
        }
    }
}

/// Der letzte Lauf als kleine Marke: grau nie, blau läuft, grün ok, rot Fehler.
struct RunChip: View {
    let r: Routine
    let now: Double
    var body: some View {
        let bad = r.last?.ok == false
        let running = r.last?.running == true
        Text(RoutinesText.lastRun(r, now: now)).font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((bad ? Color.red : running ? Color.accentColor : r.last == nil ? Color.secondary : Color.green).opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// Details einer Routine: Zeitplan, Beschreibung, Schalter, Anweisung, Angaben, letzter Lauf, „Jetzt ausführen“.
struct RoutineDetailView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var store = RoutinesStore.shared
    let id: String
    @State private var running = false
    @State private var message: String?
    @State private var opening = false

    private var now: Double { Date().timeIntervalSince1970 }

    var body: some View {
        if let r = store.info.routines.first(where: { $0.id == id }) {
            content(r)
        } else {
            Text("Diese Routine gibt es nicht mehr.").foregroundStyle(.secondary).navigationTitle("Routine")
        }
    }

    private func content(_ r: Routine) -> some View {
        List {
            Section {
                Text(r.title).font(.title3.weight(.semibold))
                Text(RoutinesText.schedule(r, now: now)).font(.footnote).foregroundStyle(.secondary)
                if !r.description.isEmpty { Text(r.description) }
                if !r.isSystem {
                    Toggle("Aktiv", isOn: Binding(get: { r.enabled }, set: { on in
                        Task { message = await store.set(r, enabled: on, model: model).map { "Nicht geändert: \($0)" } }
                    }))
                }
            }
            if !r.note.isEmpty { Section("Anweisung") { Text(r.note) } }
            Section("Angaben") {
                LabeledContent("Besitzer", value: RoutinesLabels.owner(r.owner))
                LabeledContent("Art", value: RoutinesLabels.kind(r.kind))
                LabeledContent("Modus", value: r.mode)
                LabeledContent("Zustellung", value: RoutinesLabels.deliver(r.deliver))
                if !r.builtin.isEmpty { LabeledContent("Eingebaut", value: r.builtin) }
            }
            Section("Letzter Lauf") {
                Text(RoutinesText.lastRun(r, now: now))
                if let l = r.last, !l.summary.isEmpty { Text(l.summary).font(.footnote) }
                if let h = r.last?.handoff {
                    Button { Task { await openHandoff(h) } } label: {
                        HStack { Label("Handoff \(h): Sitzung öffnen", systemImage: "bubble.left.and.bubble.right"); if opening { Spacer(); ProgressView().controlSize(.small) } }
                    }.disabled(opening)
                }
            }
            Section {
                if r.isSystem {
                    Text("Ein systemd-Timer läuft nur über systemd; Relay zeigt ihn nur an.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button { Task { await run(r) } } label: {
                        HStack {
                            if running { ProgressView().controlSize(.small) }
                            Label(running ? "Startet…" : "Jetzt ausführen", systemImage: "play.fill")
                        }
                    }
                    .disabled(running).accessibilityIdentifier("routineRun")
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Routine")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run(_ r: Routine) async {
        running = true
        message = nil
        defer { running = false }
        do { message = try await store.run(r, model: model) }
        catch { message = "Nicht gestartet: \(error.localizedDescription)" }
    }

    private func openHandoff(_ id: String) async {
        opening = true
        defer { opening = false }
        if let key = await store.sessionKey(handoff: id, model: model), model.session(for: key) != nil {
            model.openChat = key
        } else {
            message = "Zu Handoff \(id) ist keine Sitzung mehr in der Liste."
        }
    }
}

/// „Neue Routine“: Martin beschreibt in Worten, was wann laufen soll; der Chef schreibt den Eintrag und lässt bestätigen.
struct NewRoutineSheet: View {
    @Environment(\.dismiss) private var dismiss
    let send: (String) async -> String?
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Beschreibe, was wann laufen soll. Der Chef-Agent schreibt den Eintrag in die Routinen-Datei und fragt dich vor dem Aktivieren.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("Jeden Freitag um 17 Uhr die Woche zusammenfassen…", text: $text, axis: .vertical).lineLimit(3...8)
                        .accessibilityIdentifier("routineText")
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .navigationTitle("Neue Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sende…" : "An den Chef") {
                        Task {
                            sending = true
                            defer { sending = false }
                            if let e = await send(text) { error = e } else { dismiss() }
                        }
                    }
                    .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
