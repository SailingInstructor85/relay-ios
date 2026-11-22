import SwiftUI
import RelayCore

/// Der Tab-Rahmen der App: Heute, Dein Zug, Sitzungen, Posteingang, Mehr. Jeder Tab hat seinen eigenen Stapel
/// (`TabStack`), der Zustand liegt im `AppRouter`. Sprünge aus Mitteilungen und Kurzbefehlen (`openChat`,
/// `openNotice`, `openJarvis`, `openDrive` im Modell) landen hier und wählen Tab und Stapel.
struct RootTabs: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var approvals = Approvals.shared
    @ObservedObject private var notices = NoticeStore.shared

    /// Zahl am Tab „Dein Zug“: alles, was auf eine Antwort wartet (`YourTurn`). Freigaben und Hinweise werden oben
    /// beobachtet, damit die Zahl mit ihnen mitgeht.
    private var yourTurnCount: Int { YourTurnData.items(model).count }

    var body: some View {
        TabView(selection: Binding(get: { router.tab }, set: { router.select($0) })) {
            tab(.today) { TodayView() }
            tab(.yourTurn) { YourTurnView() }
                .badge(TabRouting.badge(yourTurnCount).map { Text($0) })
            tab(.sessions) { SessionsView() }
            tab(.inbox) { InboxView() }
            tab(.more) { MoreView() }
        }
        .tint(RelayColor.primary)
        // Marke für die UI-Tests (nur im Testmodus): verbunden und Sitzungen geladen
        .overlay(alignment: .topLeading) { HomeReadyMarker(ready: model.state == .connected && !model.sessions.isEmpty) }
        .onChange(of: router.tab) { old, t in
            UsageRecorder.shared.record("app", "tab", detail: t.rawValue)
            // Posteingang verlassen: Was dort stand, gilt beim nächsten Besuch nicht mehr als neu.
            if old == .inbox { InboxStore.shared.visited() }
        }
        .onChange(of: model.showDormant) { _, _ in Task { await model.refresh() } }
        .onChange(of: model.showBackground) { _, _ in Task { await model.refresh() } }
        .onChange(of: model.openChat) { _, key in
            if let key { router.jump(.chat(key)); model.openChat = nil }
        }
        .onChange(of: model.openNotice) { _, ref in
            if let ref { openNotice(ref) }
        }
        .onChange(of: model.openJarvis) { _, open in
            if open { router.jump(.jarvis); model.openJarvis = false }
        }
        .onChange(of: model.openDrive) { _, open in
            if open { router.jump(.drive); model.openDrive = false }
        }
        .onAppear {
            if let ref = model.openNotice { openNotice(ref) }
            if model.openJarvis { router.jump(.jarvis); model.openJarvis = false }
            if model.openDrive { router.jump(.drive); model.openDrive = false }
        }
    }

    /// Ein Tab mit eigenem Stapel, Beschriftung und Symbol.
    private func tab<Root: View>(_ t: AppTab, @ViewBuilder _ root: @escaping () -> Root) -> some View {
        TabStack(tab: t, root: root)
            .toolbarBackground(RelayColor.surfaceContainer, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .tabItem { Label(t.title, systemImage: t.symbol) }
            .tag(t)
    }

    /// Eine Rückfrage, die noch auf Antwort wartet, öffnet sich in „Dein Zug“, jeder andere Hinweis in „Mehr“.
    private func openNotice(_ ref: String) {
        let n = notices.get(ref)
        let open = n.map { $0.answer == nil && (Rueckfrage.question($0)?.wantsAnswer ?? false) } ?? false
        router.jump(.notice(ref: ref, openQuestion: open))
        model.openNotice = nil
    }
}

/// Seitentitel eines Tabs: links in Serifenschrift wie im Vorbild. Der Systemtitel bleibt gesetzt (er beschriftet den
/// Zurück-Knopf der Unterseiten), wird in der Leiste aber durch ein leeres Element ersetzt.
private struct RootTitle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("").accessibilityHidden(true) }
                ToolbarItem(placement: .topBarLeading) {
                    Text(title).font(RelayFont.headline).foregroundStyle(RelayColor.onSurface)
                        .fixedSize()
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .relayPage()
    }
}

extension View {
    /// Serif-Titel links in der Titelzeile, warmer Seitenhintergrund. Für die Wurzelansicht eines Tabs.
    func relayRootTitle(_ title: String) -> some View { modifier(RootTitle(title: title)) }
}

/// Ruhiger Leerzustand für einen ganzen Tab: Symbol im Kreis, Titel, ein Satz.
struct TabEmptyState: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(RelayColor.onSurfaceVariant)
                .frame(width: 64, height: 64)
                .background(RelayColor.surfaceContainerLow, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(RelayFont.titleLarge).foregroundStyle(RelayColor.onSurface)
            Text(text).font(RelayFont.bodyMedium).foregroundStyle(RelayColor.onSurfaceVariant).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
