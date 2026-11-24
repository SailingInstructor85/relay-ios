import SwiftUI
import RelayCore

/// „Smart Home“ im Tab „Mehr“: Fernseher ein, aus, HDMI 2, Fernsehen. Die App schaltet nicht selbst: Sie schickt
/// dem Gateway den Namen einer fest hinterlegten Aktion (rpc `smart_home`), das Gateway startet am PC sein Skript
/// und meldet dessen Ausgabe zurück. Die Rückmeldung steht oben, damit sie ohne Scrollen sichtbar ist.
struct SmartHomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var running: SmartHome.Action?
    @State private var outcome: SmartHome.Outcome?
    @State private var lastTitle = ""

    var body: some View {
        let connected = model.state == .connected
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                status
                SectionLabel(title: "Fernseher")
                MoreGroup {
                    ForEach(Array(SmartHome.tv.enumerated()), id: \.element.id) { i, action in
                        if i > 0 { MoreDivider() }
                        MoreRow(title: action.title, symbol: action.symbol, chevron: false) { Task { await run(action) } }
                            .accessibilityIdentifier("smartHome." + action.id)
                    }
                }
                .disabled(running != nil || !connected)
                Text(connected
                     ? "Der PC schaltet den Fernseher über das Heimnetz. \(SmartHome.slowNote)"
                     : "Keine Verbindung zum PC. Der Fernseher lässt sich nur über den PC schalten.")
                    .font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant)
                    .padding(.horizontal, RelaySpace.page).padding(.top, 10).padding(.bottom, 24)
            }
        }
        .navigationTitle("Smart Home")
        .navigationBarTitleDisplayMode(.inline)
        .relayPage()
        .onAppear { UsageRecorder.shared.screen("smarthome") }
    }

    /// Was gerade läuft oder was die letzte Aktion gemeldet hat.
    @ViewBuilder private var status: some View {
        if let action = running {
            HStack(alignment: .top, spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.running).font(RelayFont.bodyMedium).foregroundStyle(RelayColor.onSurface)
                    Text(SmartHome.slowNote).font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .relayCard()
            .padding(.horizontal, RelaySpace.rowOuter).padding(.top, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("smartHomeRunning")
        } else if let o = outcome {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: o.ok ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(o.ok ? RelayColor.primary : RelayColor.error).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lastTitle).font(RelayFont.labelMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                    Text(verbatim: o.text).font(RelayFont.bodyMedium)
                        .foregroundStyle(o.ok ? RelayColor.onSurface : RelayColor.error)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .relayCard()
            .padding(.horizontal, RelaySpace.rowOuter).padding(.top, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("smartHomeResult")
        }
    }

    private func run(_ action: SmartHome.Action) async {
        guard running == nil else { return }
        running = action
        outcome = nil
        lastTitle = action.title
        UsageRecorder.shared.record("smarthome", "aktion", kind: action.id)
        defer { running = nil }
        do {
            let reply = try await model.rpc(SmartHome.rpc, SmartHome.params(action), timeout: SmartHome.timeout)
            outcome = SmartHome.outcome(reply, action: action)
        } catch {
            let e = error as? RelayError
            outcome = SmartHome.failure(message: e?.message ?? error.localizedDescription, remote: e?.remote ?? false)
        }
        if let o = outcome, !o.ok { UsageRecorder.shared.record("smarthome", "fehler", kind: action.id, error: o.text) }
    }
}
