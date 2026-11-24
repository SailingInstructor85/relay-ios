import SwiftUI
import RelayCore

/// Ziele der Navigation. Früher `SessionsView.Dest`, jetzt `Route` aus RelayCore.
typealias Dest = Route

/// Navigation der App: der gewählte Tab und je Tab ein eigener Stapel von Unterseiten. Sprünge von außen
/// (Mitteilung, Kurzbefehl) wählen Tab und Stapel nach `TabRouting.target`.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var tab: AppTab = .today
    @Published private(set) var paths: [AppTab: [Route]] = [:]

    private init() {}

    func path(_ tab: AppTab) -> [Route] { paths[tab] ?? [] }

    /// Bindung für `NavigationStack(path:)` eines Tabs.
    func binding(_ tab: AppTab) -> Binding<[Route]> {
        Binding(get: { [weak self] in self?.paths[tab] ?? [] },
                set: { [weak self] in self?.paths[tab] = $0 })
    }

    /// Schiebt eine Unterseite auf den Stapel des Tabs (ohne den Tab zu wechseln).
    func push(_ route: Route, in tab: AppTab) {
        paths[tab, default: []].append(route)
    }

    /// Zurück zur Wurzel des Tabs.
    func popToRoot(_ tab: AppTab) {
        if !(paths[tab] ?? []).isEmpty { paths[tab] = [] }
    }

    /// Wählt einen Tab. Ein Tipp auf den schon gewählten Tab führt zu dessen Wurzel zurück.
    func select(_ new: AppTab) {
        if new == tab { popToRoot(new) } else { tab = new }
    }

    /// Wechselt in einen Tab und zeigt dessen Wurzel.
    func show(_ tab: AppTab) {
        popToRoot(tab)
        self.tab = tab
    }

    /// Sprung von außen: Tab wählen, dessen Stapel ersetzen.
    func jump(_ jump: Jump) {
        let t = TabRouting.target(jump)
        paths[t.tab] = t.path
        tab = t.tab
    }
}

/// Der Stapel eines Tabs: Wurzelansicht plus alle Unterseiten (`Route`).
struct TabStack<Root: View>: View {
    let tab: AppTab
    @ObservedObject private var router = AppRouter.shared
    @ViewBuilder var root: () -> Root

    var body: some View {
        NavigationStack(path: router.binding(tab)) {
            root()
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route, tab: tab)
                        .toolbar(route.hidesTabBar ? .hidden : .automatic, for: .tabBar)
                }
        }
    }
}

/// Baut die Ansicht zu einem Ziel. Rückrufe der Ansichten (Hinweis öffnen, Sprachmodus) bleiben im Stapel des Tabs.
struct RouteView: View {
    let route: Route
    let tab: AppTab
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        switch route {
        case .chat(let key): ChatView(sessionKey: key)
        case .chatSearch(let key, let q): ChatView(sessionKey: key, initialSearch: q)
        case .settings: SetupView()
        case .usage: UsageView()
        case .memory: MemoryView()
        case .digest: DigestView()
        case .tokens: TokensView()
        case .jarvis: JarvisView()
        case .jarvisListening: JarvisView(autoListen: true)
        case .jarvisAsk(let q): JarvisView(initialQuestion: q)
        case .jarvisSend(let shown, let text): JarvisView(initialQuestion: text, initialShown: shown)
        case .notices: notice(nil)
        case .notice(let ref): notice(ref)
        case .drive: DriveView()
        case .vaultChat: VaultChatView()
        case .routines: RoutinesView()
        case .mail(let id): MailView(id: id)
        case .calendar: CalendarWeekView()
        }
    }

    private func notice(_ ref: String?) -> some View {
        NoticeView(ref: ref,
                   onOpen: { router.push(.notice($0), in: tab) },
                   onGo: go,
                   onDrive: { router.push(.drive, in: tab) })
    }

    private func go(_ g: NoticeLogic.Goto) {
        switch g {
        case .accounts: router.push(.usage, in: tab)
        case .jarvis: router.push(.jarvis, in: tab)
        case .sessions: router.show(.sessions)
        case .none: break
        }
    }
}
