import SwiftUI
import RelayCore

/// Tab „Mehr“: das frühere Hauptmenü der Sitzungsliste als Seite. Assistent, Hinweise, Routinen, Einstellungen,
/// die Übersichten und die Aktionen für alle Sitzungen und den Desktop.
struct MoreView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var notices = NoticeStore.shared
    @State private var showPower = false
    @State private var showWindDown = false

    private func push(_ r: Route) { router.push(r, in: .more) }

    var body: some View {
        let connected = model.state == .connected
        let openQuestions = DriveQueue.open(notices.items).count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Einstellungen bewusst weit oben: am Ende einer langen Seite liegt der Eintrag unter dem Rand.
                MoreGroup {
                    MoreRow(title: "Jarvis fragen", symbol: "waveform") { push(.jarvis) }
                    MoreDivider()
                    MoreRow(title: "Hinweise", symbol: "bell.badge",
                            detail: openQuestions == 0 ? nil : (openQuestions == 1 ? "1 Rückfrage" : "\(openQuestions) Rückfragen")) { push(.notices) }
                    MoreDivider()
                    MoreRow(title: "Routinen", symbol: "calendar.badge.clock") { push(.routines) }
                    MoreDivider()
                    MoreRow(title: "Einstellungen", symbol: "gear") { push(.settings) }
                }
                .padding(.top, 8)

                SectionLabel(title: "Übersichten")
                MoreGroup {
                    MoreRow(title: "Nutzung & Limits", symbol: "gauge.with.dots.needle.33percent") { push(.usage) }
                    MoreDivider()
                    MoreRow(title: "RAM-Monitor", symbol: "memorychip") { push(.memory) }
                    MoreDivider()
                    MoreRow(title: "Was war los", symbol: "newspaper") { push(.digest) }
                    MoreDivider()
                    MoreRow(title: "Token-Verbrauch", symbol: "chart.bar") { push(.tokens) }
                }

                SectionLabel(title: "Sitzungen")
                MoreGroup {
                    MoreRow(title: "Alle gelesen", symbol: "checkmark.circle", chevron: false) { model.markAllRead() }
                        .disabled(model.unread.isEmpty)
                    MoreDivider()
                    MoreRow(title: "Hintergrundläufe", symbol: "moon.zzz", chevron: false, checked: model.showBackground) {
                        model.showBackground.toggle()
                    }
                    MoreDivider()
                    MoreRow(title: "Neu verbinden", symbol: "arrow.clockwise", chevron: false) { model.reconnect() }
                    MoreDivider()
                    MoreRow(title: "Alle Sitzungen beenden ...", symbol: "xmark.circle", chevron: false) { showWindDown = true }
                        .disabled(!connected)
                }

                SectionLabel(title: "Desktop")
                MoreGroup {
                    MoreRow(title: "Desktop ausschalten ...", symbol: "power", chevron: false) { showPower = true }
                        .disabled(!connected)
                }

                Text("Relay \(AppModel.appVersion)").font(RelayFont.labelSmall).foregroundStyle(RelayColor.outline)
                    .frame(maxWidth: .infinity).padding(.top, 20).padding(.bottom, 24)
            }
        }
        .relayRootTitle(AppTab.more.title)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ConnDot() } }
        .onAppear { UsageRecorder.shared.screen("mehr") }
        .sheet(isPresented: $showPower) { PowerView().environmentObject(model) }
        .sheet(isPresented: $showWindDown) { WindDownView().environmentObject(model) }
    }
}

/// Eine Gruppe von Zeilen auf einer Kartenfläche.
struct MoreGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .relayCard()
            .padding(.horizontal, RelaySpace.rowOuter)
    }
}

struct MoreDivider: View {
    var body: some View {
        Rectangle().fill(RelayColor.outlineVariant).frame(height: 1).padding(.leading, 52)
    }
}

/// Eine antippbare Zeile: Symbol in Akzentfarbe, Titel, rechts Zusatztext, Haken oder Pfeil.
struct MoreRow: View {
    let title: String
    let symbol: String
    var detail: String?
    var chevron = true
    var checked = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(RelayColor.primary)
                    .frame(width: 28).accessibilityHidden(true)
                Text(title).font(RelayFont.bodyLarge).foregroundStyle(RelayColor.onSurface)
                Spacer(minLength: 8)
                if let detail { Text(detail).font(RelayFont.labelMedium).foregroundStyle(RelayColor.onSurfaceVariant) }
                if checked { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(RelayColor.primary).accessibilityLabel("an") }
                if chevron { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(RelayColor.outline).accessibilityHidden(true) }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: RelaySpace.optionMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
    }
}
