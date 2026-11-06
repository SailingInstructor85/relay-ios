import SwiftUI
import RelayCore

/// "Alle Sitzungen beenden ...": pick the sessions, confirm, then watch each one get the closing message, write its
/// handover and end (gateway `wind_down`, WindDown in RelayCore). The gateway runs the job, so it finishes even when
/// the app goes away; this view only shows the progress and the summary.
struct WindDownView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var preselected = false
    @State private var confirm = false
    @State private var starting = false
    @State private var error: String?

    private var candidates: [Session] { WindDown.candidates(Array(model.sessions.values)) }
    private var chosen: [Session] { candidates.filter { selected.contains($0.key) } }
    private var picking: Bool { model.windDownJob == nil }

    var body: some View {
        NavigationStack {
            List {
                if picking { picker } else { progress }
            }
            .safeAreaInset(edge: .bottom) {
                // The start button sits below the list, not at its end: with many sessions the end is off screen.
                if picking && !candidates.isEmpty { startBar }
            }
            .navigationTitle("Alle Sitzungen beenden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(model.windDownDone ? "Fertig" : "Schließen") { if model.windDownDone { model.clearWindDown() }; dismiss() }
                }
            }
            .onAppear {
                if !preselected { preselected = true; selected = WindDown.preselected(candidates) }
            }
            .task(id: model.windDownJob) {
                // events carry each phase; the poll catches up after a lost link
                while let _ = model.windDownJob, !model.windDownDone, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await model.refreshWindDown()
                }
            }
            .confirmationDialog(WindDown.confirmTitle(chosen.count), isPresented: $confirm, titleVisibility: .visible) {
                Button(WindDown.confirmButton, role: .destructive) { Task { await start() } }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(chosen.map(\.name).joined(separator: "\n"))
            }
        }
    }

    // MARK: picking

    @ViewBuilder private var picker: some View {
        if candidates.isEmpty {
            Section { Text("Keine offenen Sitzungen.").foregroundStyle(.secondary) }
        } else {
            Section {
                ForEach(candidates) { s in
                    let e = WindDown.eligibility(s)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).lineLimit(1)
                            HStack(spacing: 6) {
                                Tag(text: s.alias)
                                Text(s.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            if !e.note.isEmpty { Text(e.note).font(.caption).foregroundStyle(e.selectable ? .orange : .secondary) }
                        }
                        Spacer()
                        if e.selectable {
                            Toggle("", isOn: Binding(get: { selected.contains(s.key) },
                                                     set: { if $0 { selected.insert(s.key) } else { selected.remove(s.key) } }))
                                .labelsHidden()
                                .accessibilityLabel(s.name)
                                .accessibilityIdentifier("windDownToggle:" + s.key)
                        }
                    }
                    .opacity(e.selectable ? 1 : 0.55)
                }
            } header: {
                Text("Sitzungen")
            } footer: {
                Text("Jede gewählte Sitzung bekommt die Abschlussnachricht: Offenes festhalten (Stand, offene Punkte, nächster Schritt in die Projektnotiz oder Übergabe), dann wird sie beendet. Arbeitende Sitzungen werden nicht abgebrochen, das Gateway wartet das Ende der Runde ab. Stellt ein Agent eine Rückfrage, bleibt seine Sitzung offen.")
            }
        }
    }

    /// Always visible while picking: the count of chosen sessions and the button that asks for the confirmation.
    private var startBar: some View {
        VStack(spacing: 6) {
            if let e = error { Text(e).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center) }
            Button(role: .destructive) { confirm = true } label: {
                HStack {
                    if starting { ProgressView().padding(.trailing, 4) }
                    Label(WindDown.buttonTitle(chosen.count), systemImage: "xmark.circle")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(chosen.isEmpty || starting || model.state != .connected)
            .accessibilityIdentifier("windDownStart")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func start() async {
        starting = true; defer { starting = false }
        do { try await model.startWindDown(chosen.map(\.key)); error = nil }
        catch { self.error = "Nicht gestartet: \(error.localizedDescription)" }
    }

    // MARK: progress

    @ViewBuilder private var progress: some View {
        Section {
            ForEach(model.windDownItems) { i in
                HStack(alignment: .top, spacing: 10) {
                    icon(i.phase)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(i.title.isEmpty ? model.session(for: i.key)?.name ?? i.key : i.title).lineLimit(1)
                        Text(i.statusLine).font(.caption).foregroundStyle(color(i.phase)).textSelection(.enabled)
                    }
                }
            }
        } header: {
            HStack { Text(model.windDownDone ? "Ergebnis" : "Läuft"); if !model.windDownDone { ProgressView().controlSize(.small) } }
        } footer: {
            if !model.windDownDone { Text("Das Gateway führt das zu Ende, auch wenn die App geschlossen wird.") }
        }
        if model.windDownDone {
            Section("Zusammenfassung") {
                Text(WindDown.summary(model.windDownItems)).font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("windDownSummary")
            }
        }
    }

    @ViewBuilder private func icon(_ p: WindDown.Phase) -> some View {
        switch p {
        case .closed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .question: Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
        case .timeout: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .error: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .queued: Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        default: ProgressView().controlSize(.small)
        }
    }

    private func color(_ p: WindDown.Phase) -> Color {
        switch p {
        case .closed: return .secondary
        case .question, .timeout: return .orange
        case .error: return .red
        default: return .secondary
        }
    }
}
