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
                // The start button and, later, the result sit below the list, not at its end: with many sessions the
                // end of the list is off screen.
                if picking { if !candidates.isEmpty { startBar } } else { resultBar }
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
                    let on = selected.contains(s.key)
                    // a row is a button with a check mark (not a Toggle): one tap picks or drops the session
                    Button {
                        guard e.selectable else { return }
                        if on { selected.remove(s.key) } else { selected.insert(s.key) }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: e.selectable ? (on ? "checkmark.circle.fill" : "circle") : "minus.circle")
                                .font(.title3)
                                .foregroundStyle(e.selectable ? (on ? Color.accentColor : Color.secondary) : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).lineLimit(1).foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    Tag(text: s.alias)
                                    Text(s.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                if !e.note.isEmpty { Text(e.note).font(.caption).foregroundStyle(e.selectable ? .orange : .secondary) }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!e.selectable)
                    .opacity(e.selectable ? 1 : 0.55)
                    .accessibilityLabel(s.name)
                    .accessibilityValue(e.selectable ? (on ? "gewählt" : "nicht gewählt") : "nicht wählbar")
                    .accessibilityIdentifier("windDownPick:" + s.key)
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

    /// While the job runs: how many are through; when it is done: the first line of the summary and "Fertig".
    private var resultBar: some View {
        let items = model.windDownItems
        let through = items.filter { $0.phase.isFinal }.count
        let allGood = items.allSatisfy { $0.phase.isGood }
        let firstLine = WindDown.summary(items).components(separatedBy: "\n").first ?? ""
        return HStack(spacing: 10) {
            if model.windDownDone {
                Image(systemName: allGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(allGood ? Color.green : Color.orange)
                Text(firstLine).font(.callout).accessibilityIdentifier("windDownResult")
                Spacer()
                Button("Fertig") { model.clearWindDown(); dismiss() }.buttonStyle(.borderedProminent)
            } else {
                ProgressView().controlSize(.small)
                Text("\(through) von \(items.count) Sitzungen durch, das Gateway arbeitet weiter.").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
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
        if model.windDownDone {
            // the result first, the rows below: with many sessions the end of the list is off screen
            Section("Zusammenfassung") {
                Text(WindDown.summary(model.windDownItems)).font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("windDownSummary")
            }
        }
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
