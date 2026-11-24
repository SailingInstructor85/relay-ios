import SwiftUI
import RelayCore

/// Der Posteingang des Gateways (rpc `inbox_feed`, `inbox_mail_suggest`), einmal geladen für den Tab. Nur lesend:
/// Die App sendet, löscht und beantwortet nichts. Inhalte bleiben im Arbeitsspeicher; auf dem iPhone gemerkt wird
/// nur, welche Mails hier geöffnet wurden und wann der Tab zuletzt verlassen wurde (für die Markierung „neu“).
@MainActor
final class InboxStore: ObservableObject {
    static let shared = InboxStore()

    @Published private(set) var feed: InboxFeed?
    @Published private(set) var failure: InboxText.Failure?
    @Published private(set) var loading = false
    @Published private(set) var suggestions: [MailSuggestion] = []
    @Published private(set) var opened: Set<String>
    /// Mails mit späterer Eingangszeit gelten als neu (siehe `InboxSeen`).
    @Published private(set) var since: Double
    private(set) var loadedAt: Double = 0
    private var suggestionsAt: Double = 0
    private var loadingSuggestions = false

    private static let openedKey = "inbox.opened", sinceKey = "inbox.since"

    private init() {
        let d = UserDefaults.standard
        opened = Set(d.stringArray(forKey: Self.openedKey) ?? [])
        let s = d.double(forKey: Self.sinceKey)
        since = s > 0 ? s : InboxSeen.firstSince(now: Date().timeIntervalSince1970)
    }

    /// Lädt die Liste der letzten sieben Tage. Fehler stehen danach in `failure`; die alte Liste bleibt stehen.
    func refresh(_ model: AppModel) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let f = InboxFeed.from(try await model.rpc("inbox_feed", ["days": 7, "limit": 300], timeout: 60))
            feed = f
            failure = InboxText.sourceFailure(f)
            loadedAt = Date().timeIntervalSince1970
            let kept = InboxSeen.prune(opened, feed: f.items)
            if kept != opened, !f.items.isEmpty { opened = kept; saveOpened() }
        } catch {
            let e = error as? RelayError
            failure = InboxText.failure(message: e?.message ?? error.localizedDescription, remote: e?.remote ?? false)
        }
    }

    /// Lädt die Liste neu, wenn sie fehlt oder älter als zwei Minuten ist.
    func refreshIfStale(_ model: AppModel) async {
        if feed == nil || Date().timeIntervalSince1970 - loadedAt > 120 { await refresh(model) }
    }

    /// Aufräumvorschläge (höchstens alle 30 Minuten, so lange hält sie auch das Gateway vor). Der erste Abruf kann am
    /// PC eine Minute dauern. Scheitert er, bleibt der Abschnitt weg.
    func loadSuggestions(_ model: AppModel, force: Bool = false) async {
        let now = Date().timeIntervalSince1970
        guard !loadingSuggestions, force || now - suggestionsAt > 1800 else { return }
        loadingSuggestions = true
        defer { loadingSuggestions = false }
        if let r = try? await model.rpc("inbox_mail_suggest", [:], timeout: 150) {
            suggestions = MailSuggestion.list(r)
            suggestionsAt = now
        }
    }

    func markOpened(_ id: String) {
        guard !opened.contains(id) else { return }
        opened.insert(id)
        saveOpened()
    }

    /// Der Tab wurde verlassen: Was bis zum letzten Laden eingegangen ist, gilt beim nächsten Besuch nicht mehr als neu.
    func visited() {
        guard loadedAt > since else { return }
        since = loadedAt
        UserDefaults.standard.set(since, forKey: Self.sinceKey)
    }

    private func saveOpened() { UserDefaults.standard.set(Array(opened), forKey: Self.openedKey) }
}

/// Tab „Posteingang“: Suchfeld, Aufräumvorschläge (nur Anzeige), darunter die Mails der letzten sieben Tage nach Tag.
/// Ein Tipp öffnet die Mail zum Lesen. Vorbild ist die Inbox der Android-App (Inbox.kt), ohne Antworten und Löschen.
struct InboxView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var store = InboxStore.shared
    @ObservedObject private var router = AppRouter.shared
    @State private var query = ""
    @State private var result: InboxSearchResult?
    @State private var searching = false
    @State private var searchNote: String?
    @State private var showSuggestions = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                searchField
                if searching || result != nil || searchNote != nil {
                    searchContent
                } else {
                    feedContent
                }
            }
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await reload() }
        .relayRootTitle(AppTab.inbox.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ConnDot() }
        }
        .task {
            await store.refreshIfStale(model)
            await store.loadSuggestions(model)
        }
        .onChange(of: model.state) { _, s in
            // Beim Start steht der Tab oft vor der Verbindung: nachladen, sobald sie da ist.
            if s == .connected, store.feed == nil { Task { await store.refresh(model) } }
        }
        .onAppear { UsageRecorder.shared.screen("posteingang") }
    }

    /// Ziehen zum Aktualisieren: während einer Suche die Suche, sonst die Liste und die Vorschläge.
    private func reload() async {
        if result != nil, let q = InboxText.query(query) {
            await runSearch(q)
        } else {
            await store.refresh(model)
            await store.loadSuggestions(model)
        }
    }

    // MARK: Suche

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(RelayColor.onSurfaceVariant)
                .accessibilityHidden(true)
            TextField(InboxText.searchPlaceholder, text: $query)
                .font(RelayFont.bodyLarge)
                .foregroundStyle(RelayColor.onSurface)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { submitSearch() }
                .accessibilityIdentifier("inboxSearch")
            if searching { ProgressView().controlSize(.small) }
            if !query.isEmpty || result != nil || searchNote != nil {
                Button { endSearch() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(RelayColor.outline)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche beenden").accessibilityIdentifier("inboxSearchClear")
            }
        }
        .padding(.leading, 14).padding(.trailing, 6)
        .frame(minHeight: 44)
        .background(RelayColor.surfaceContainerLow, in: RoundedRectangle(cornerRadius: RelayRadius.search, style: .continuous))
        .padding(.horizontal, RelaySpace.rowOuter)
        .padding(.top, 8)
    }

    private func submitSearch() {
        guard let q = InboxText.query(query) else {
            result = nil
            searchNote = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : InboxText.searchTooShort
            return
        }
        searchFocused = false
        Task { await runSearch(q) }
    }

    private func runSearch(_ q: String) async {
        searching = true
        searchNote = nil
        defer { searching = false }
        do {
            let r = InboxSearchResult.from(try await model.rpc("inbox_search", ["q": .string(q), "limit": 50], timeout: 60))
            // Die Antwort gilt nur, wenn die Suche inzwischen nicht beendet oder geändert wurde.
            guard InboxText.query(query) == q else { return }
            result = r
            UsageRecorder.shared.record("posteingang", "gesucht", length: q.count)
        } catch {
            guard InboxText.query(query) == q else { return }
            let e = error as? RelayError
            let message = e?.message ?? error.localizedDescription
            result = nil
            searchNote = (e?.remote ?? false) && InboxText.isUnknownRpc(message)
                ? "Das Gateway bietet keine Suche im Posteingang an."
                : "Suche fehlgeschlagen: \(message)"
        }
    }

    private func endSearch() {
        query = ""
        result = nil
        searchNote = nil
        searchFocused = false
    }

    @ViewBuilder private var searchContent: some View {
        if let note = searchNote {
            QuietLine(text: note).padding(.top, 12).accessibilityIdentifier("inboxSearchNote")
        }
        if let r = result {
            QuietLine(text: InboxText.found(r)).padding(.top, 12).accessibilityIdentifier("inboxFound")
            if !r.mailError.isEmpty { errorLine("Mail: \(r.mailError)") }
            if r.items.isEmpty {
                QuietLine(text: InboxText.nothingFound)
            } else {
                dayList(r.items, marks: false)
            }
        } else if searching {
            QuietLine(text: "Suche läuft, über alle Jahre …").padding(.top, 12)
        }
    }

    // MARK: Liste

    @ViewBuilder private var feedContent: some View {
        if let f = store.failure, store.feed?.items.isEmpty ?? true {
            failureState(f)
        } else if let feed = store.feed {
            if let f = store.failure { errorLine(f.text) }
            if !feed.mailError.isEmpty, store.failure == nil { errorLine("Mail: \(feed.mailError)") }
            suggestionsSection
            if feed.items.isEmpty {
                TabEmptyState(symbol: "envelope.open", title: "Alles ruhig", text: InboxText.empty(days: feed.days))
                    .padding(.top, 72)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("inboxEmpty")
            } else {
                dayList(feed.items, marks: true)
            }
        } else {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.top, 96)
                .accessibilityIdentifier("inboxLoading")
        }
    }

    private func failureState(_ f: InboxText.Failure) -> some View {
        VStack(spacing: 16) {
            TabEmptyState(symbol: f.missing ? "envelope.badge" : "wifi.exclamationmark", title: f.title, text: f.text)
            Button(store.loading ? "Lädt …" : "Erneut laden") { Task { await store.refresh(model) } }
                .buttonStyle(RelayTonalButtonStyle())
                .disabled(store.loading)
                .accessibilityIdentifier("inboxRetry")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inboxFailure")
    }

    private func errorLine(_ text: String) -> some View {
        Text(text).font(RelayFont.bodySmall).foregroundStyle(RelayColor.error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RelaySpace.page).padding(.top, 8)
    }

    /// Die Zeilen in Abschnitten je Tag. `marks`: Markierung „neu“ zeigen (nur in der Liste, nicht in Suchtreffern).
    @ViewBuilder private func dayList(_ items: [InboxItem], marks: Bool) -> some View {
        let new = marks ? InboxSeen.newCount(items, since: store.since, opened: store.opened) : 0
        if new > 0 {
            Text(new == 1 ? "1 neue Mail seit deinem letzten Besuch" : "\(new) neue Mails seit deinem letzten Besuch")
                .font(RelayFont.labelMedium).foregroundStyle(RelayColor.primary)
                .padding(.horizontal, RelaySpace.page).padding(.top, 12)
                .accessibilityIdentifier("inboxNew")
        }
        ForEach(InboxText.days(items)) { day in
            SectionLabel(title: day.label)
            ForEach(day.items) { item in
                let isNew = marks && InboxSeen.isNew(item, since: store.since, opened: store.opened)
                if item.kind == .mail {
                    Button { open(item) } label: { InboxRow(item: item, isNew: isNew) }
                        .buttonStyle(.plain)
                } else {
                    InboxRow(item: item, isNew: false)
                }
            }
        }
    }

    private func open(_ item: InboxItem) {
        searchFocused = false
        store.markOpened(item.itemID)
        UsageRecorder.shared.record("posteingang", "mail geöffnet")
        router.push(.mail(item.itemID), in: .inbox)
    }

    // MARK: Aufräumvorschläge

    /// Eine Zeile, die sich aufklappt: Absender mit vielen automatischen Mails. Nur zur Ansicht, ohne Knöpfe.
    @ViewBuilder private var suggestionsSection: some View {
        let groups = store.suggestions
        if !groups.isEmpty {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showSuggestions.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tray.full").font(.system(size: 15)).foregroundStyle(RelayColor.onSurfaceVariant)
                        .frame(width: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(InboxText.suggestionsTitle).font(RelayFont.titleSmall).foregroundStyle(RelayColor.onSurface)
                        Text(InboxText.suggestionsSummary(groups)).font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: showSuggestions ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(RelayColor.outline).accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: RelaySpace.optionMinHeight)
                .relayCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, RelaySpace.rowOuter)
            .padding(.top, 10)
            .accessibilityIdentifier("inboxSuggestions")
            if showSuggestions {
                ForEach(groups) { g in SuggestionCard(group: g) }
                Text(InboxText.suggestionsNote).font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant)
                    .padding(.horizontal, RelaySpace.page).padding(.top, 6)
            }
        }
    }
}

/// Kreis mit Kürzel des Absenders in einer der zehn Avatarfarben, oben rechts der Punkt für „neu“.
struct InboxAvatar: View {
    let name: String
    let key: String
    var isNew = false

    var body: some View {
        let palette = RelayColor.avatarPalette
        Circle().fill(palette[Avatars.slot(key, size: palette.count)])
            .frame(width: RelaySpace.avatar, height: RelaySpace.avatar)
            .overlay {
                Text(InboxText.initials(name)).font(.system(size: RelaySpace.avatar * 0.38, weight: .semibold)).foregroundStyle(.white)
            }
            .overlay(alignment: .topTrailing) {
                if isNew {
                    Circle().fill(RelayColor.primary).frame(width: 11, height: 11)
                        .overlay { Circle().stroke(RelayColor.background, lineWidth: 2) }
                        .offset(x: 2, y: -2)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Eine Zeile des Posteingangs: Absender und Zeit, Betreff, Vorschau (soweit das Gateway eine liefert), unten das Konto.
struct InboxRow: View {
    let item: InboxItem
    var isNew = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            InboxAvatar(name: item.who, key: item.avatarKey, isNew: isNew)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: item.who).font(RelayFont.titleSmall).fontWeight(isNew ? .semibold : .medium)
                        .foregroundStyle(RelayColor.onSurface).lineLimit(1)
                    Spacer(minLength: 4)
                    if item.ts > 0 {
                        Text(DayText.clock(ts: item.ts)).font(RelayFont.labelMedium).monospacedDigit()
                            .foregroundStyle(isNew ? RelayColor.primary : RelayColor.onSurfaceVariant).layoutPriority(1)
                    }
                }
                if !item.headline.isEmpty {
                    Text(verbatim: item.headline).font(RelayFont.bodyMedium).fontWeight(isNew ? .medium : .regular)
                        .foregroundStyle(RelayColor.onSurface).lineLimit(1)
                }
                if !item.preview.isEmpty {
                    Text(verbatim: item.preview).font(RelayFont.bodyMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                HStack(spacing: 6) {
                    if !item.footer.isEmpty {
                        Text(verbatim: item.footer).font(RelayFont.labelSmall).foregroundStyle(RelayColor.primary).lineLimit(1)
                    }
                    if item.attachments {
                        Image(systemName: "paperclip").font(.system(size: 11)).foregroundStyle(RelayColor.onSurfaceVariant)
                            .accessibilityLabel("mit Anhang")
                    }
                    if isNew {
                        Text("neu").font(RelayFont.labelSmall).foregroundStyle(RelayColor.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .relayCard(isNew ? RelayColor.surfaceContainerHigh : RelayColor.background)
        .padding(.horizontal, RelaySpace.rowOuter)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inboxRow")
    }
}

/// Ein Aufräumvorschlag als Karte: Absender, Anzahl und Grund, bis zu drei Betreffs als Beispiel. Ohne Aktionen.
struct SuggestionCard: View {
    let group: MailSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: group.sender).font(RelayFont.titleSmall).foregroundStyle(RelayColor.onSurface).lineLimit(1)
            Text(group.line).font(RelayFont.labelMedium).foregroundStyle(RelayColor.primary).lineLimit(1)
            ForEach(Array(group.examples.prefix(3).enumerated()), id: \.offset) { _, subject in
                Text(verbatim: subject).font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .relayCard()
        .padding(.horizontal, RelaySpace.rowOuter)
        .padding(.top, RelaySpace.cardGap)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inboxSuggestion")
    }
}

/// Eine Mail zum Lesen (rpc `inbox_mail`): Betreff, Kopf, Anhänge mit Namen, der Text als reiner Text. Der Inhalt
/// ist fremd: keine Auszeichnung, keine Bilder, nichts wird von selbst geladen. Im Text lassen sich Stellen
/// markieren und kopieren. Links (nur http, https, mailto) öffnen sich erst auf Tippen; langes Drücken zeigt die
/// Zieladresse, und wo der Text über das Ziel täuschen kann, fragt die App vor dem Öffnen. Antworten und Löschen
/// gibt es hier nicht.
struct MailView: View {
    let id: String
    @EnvironmentObject var model: AppModel
    @State private var mail: MailMessage?
    @State private var error: String?
    @State private var loading = false
    /// Der Text in einem Stück (Absätze durch Leerzeilen getrennt) und die Links darin.
    @State private var text = ""
    @State private var links: [MailLink] = []
    /// Link, dessen Zieladresse gerade gezeigt wird (langes Drücken oder Warnung vor dem Öffnen).
    @State private var asking: MailLink?
    /// UI-Test: Was geöffnet worden wäre (dort verlässt die App den Simulator nicht).
    @State private var openedNote: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let m = mail {
                    header(m)
                    if let openedNote {
                        Text(verbatim: "Geöffnet: \(openedNote)").font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant)
                            .accessibilityIdentifier("mailLinkOpened")
                    }
                    if !text.isEmpty {
                        MailBodyText(text: text, links: links, onTap: { tapped($0) }, onHold: { asking = $0 })
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !links.isEmpty {
                        Text("Links öffnen sich erst, wenn du sie antippst. Langes Drücken zeigt die Zieladresse.")
                            .font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant)
                    }
                    if m.paragraphs.isEmpty {
                        Text("Diese Mail hat keinen Text.").font(RelayFont.bodyMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                    }
                    if m.truncated {
                        Text("Der Text ist gekürzt. Die ganze Mail steht im Mailprogramm.")
                            .font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant)
                    }
                } else if let error {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mail nicht geladen").font(RelayFont.titleLarge).foregroundStyle(RelayColor.onSurface)
                        Text(error).font(RelayFont.bodyMedium).foregroundStyle(RelayColor.error)
                        Button("Erneut laden") { Task { await load() } }.buttonStyle(RelayTonalButtonStyle())
                    }
                    .accessibilityIdentifier("mailError")
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 80)
                }
            }
            .padding(.horizontal, RelaySpace.page)
            .padding(.vertical, 12)
        }
        .navigationTitle("Mail")
        .navigationBarTitleDisplayMode(.inline)
        .relayPage()
        .task(id: id) { await load() }
        .onAppear { UsageRecorder.shared.screen("mail") }
        .confirmationDialog(asking?.warning == nil ? "Link" : "Vorsicht bei diesem Link",
                            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { link in
            Button(link.isMail ? "Mail schreiben" : "In Safari öffnen") { open(link) }
            Button("Adresse kopieren") { UIPasteboard.general.string = link.isMail ? link.host : link.target }
            Button("Abbrechen", role: .cancel) {}
        } message: { link in
            Text(verbatim: (link.warning.map { $0 + "\n\n" } ?? "") + "Ziel: " + (link.isMail ? link.host : link.target))
        }
    }

    /// Tipp auf einen Link: gleich öffnen, außer der Text kann über das Ziel täuschen. Dann zuerst die Adresse zeigen.
    private func tapped(_ link: MailLink) {
        if link.warning != nil { asking = link } else { open(link) }
    }

    /// Öffnet einen Link im Browser (mailto im Mailprogramm). Nur auf Martins Tippen, nur http, https und mailto.
    private func open(_ link: MailLink) {
        guard let url = MailBodyText.url(link) else { return }
        UsageRecorder.shared.record("mail", "link geöffnet", kind: link.isMail ? "mailto" : "web")
        if UITestMode.active { openedNote = link.target; return }
        UIApplication.shared.open(url)
    }

    private func header(_ m: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: m.title).font(RelayFont.titleLarge).foregroundStyle(RelayColor.onSurface)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("mailSubject")
            VStack(alignment: .leading, spacing: 4) {
                field("Von", m.from)
                field("An", m.to)
                field("Datum", InboxText.when(m.ts))
                field("Konto", m.account)
            }
            if !m.attachments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(m.attachments.enumerated()), id: \.offset) { _, name in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "paperclip").font(.system(size: 12)).foregroundStyle(RelayColor.onSurfaceVariant)
                                .accessibilityHidden(true)
                            Text(verbatim: name).font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurface).lineLimit(2)
                        }
                    }
                    Text("Anhänge lassen sich hier nicht öffnen.").font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .relayCard()
    }

    @ViewBuilder private func field(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).font(RelayFont.labelMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                    .frame(width: 48, alignment: .leading)
                Text(verbatim: value).font(RelayFont.bodyMedium).foregroundStyle(RelayColor.onSurface)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let r = try await model.rpc("inbox_mail", ["id": .string(id)], timeout: 60)
            if let m = MailMessage.from(r) {
                let t = m.paragraphs.joined(separator: "\n\n")
                text = t
                links = MailLinks.find(t)
                mail = m
                error = nil
            } else {
                error = "Das Gateway hat keine Mail geliefert."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
