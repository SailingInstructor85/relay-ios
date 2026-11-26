import SwiftUI
import RelayCore

/// Der Kalender des Gateways (rpc `calendar`), einmal geladen für die Karte auf „Heute“ und die Wochenliste. Nur
/// lesend. Geladen werden acht Tage ab heute. Jede Antwort wird auf dem iPhone gespeichert (`calendar-cache.json`):
/// Beim Start und ohne Verbindung zum PC zeigt die App diesen Stand mit dem Hinweis „Stand von …“ (`CalendarCache`).
@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()
    /// Heute plus die sieben Tage der Wochenliste.
    static let days = 8

    @Published private(set) var feed: CalendarFeed?
    /// Text für die Anzeige, wenn der Abruf gescheitert ist.
    @Published private(set) var failure: String?
    /// Das Gateway kennt den RPC `calendar` nicht.
    @Published private(set) var missing = false
    @Published private(set) var loading = false
    /// Zeitpunkt des Abrufs von `feed` (Unix-Sekunden), auch bei einem Stand aus dem Zwischenspeicher.
    @Published private(set) var fetchedAt: Double = 0
    /// `feed` stammt aus dem Zwischenspeicher, oder der letzte Abruf ist gescheitert.
    @Published private(set) var stale = false
    /// Letzter gelungener Abruf in diesem Lauf der App (für „älter als fünf Minuten“).
    private var loadedAt: Double = 0

    private init() {
        _ = AppModel.shared  // im UI-Test räumt dessen Start die Ablage der App erst leer
        guard let u = Self.cacheURL, let d = try? Data(contentsOf: u), let snap = CalendarCache.decode(d),
              CalendarCache.usable(snap.feed, today: DayText.key(Date())) else { return }
        feed = snap.feed
        fetchedAt = snap.at
        stale = true
    }

    private static var cacheURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("calendar-cache.json")
    }

    /// „Stand von …“, wenn der gezeigte Stand nicht frisch ist (Zwischenspeicher, gescheiterter Abruf, keine
    /// Verbindung). nil: frisch geladen, oder es gibt keinen Stand.
    func staleNote(connected: Bool, now: Date) -> String? {
        guard feed != nil else { return nil }
        return CalendarCache.staleNote(at: fetchedAt, stale: stale, connected: connected, now: now.timeIntervalSince1970)
    }

    /// Lädt neu, wenn noch nichts da ist, der Stand älter als fünf Minuten ist oder der Tag gewechselt hat.
    /// `force`: sofort laden. `sync`: Das Gateway holt die Kalender vorher frisch ab (dauert etwa zehn Sekunden).
    /// Scheitert der Abruf, bleibt der bisherige Stand stehen.
    func refresh(_ model: AppModel, force: Bool = false, sync: Bool = false) async {
        let today = DayText.key(Date())
        let now = Date().timeIntervalSince1970
        let fresh = feed.map { $0.covers(today, days: Self.days) && now - loadedAt < 300 } ?? false
        guard !loading, force || sync || !fresh else { return }
        loading = true
        defer { loading = false }
        do {
            let params: JSON = ["from": .string(today), "days": .number(Double(Self.days)), "refresh": .bool(sync)]
            let response = try await model.rpc("calendar", params, timeout: sync ? 90 : 45)
            feed = CalendarFeed.from(response)
            failure = nil
            missing = false
            loadedAt = now
            fetchedAt = now
            stale = false
            if let u = Self.cacheURL, let d = CalendarCache.encode(response, at: now) { try? d.write(to: u, options: .atomic) }
        } catch {
            let e = error as? RelayError
            let message = e?.message ?? error.localizedDescription
            missing = (e?.remote ?? false) && InboxText.isUnknownRpc(message)
            failure = Agenda.failureLine(message: message, remote: e?.remote ?? false)
            if feed != nil { stale = true }
        }
    }
}

/// Farbbalken eines Kalenders; ohne Farbe vom Gateway der Akzent.
private struct CalendarBar: View {
    let hex: UInt32?
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(hex.map { Color(hex: $0) } ?? RelayColor.primary)
            .frame(width: 4)
            .accessibilityHidden(true)
    }
}

/// Ein Termin als Zeile: Farbbalken des Kalenders, links die Zeit (Beginn, darunter das Ende), rechts Titel und
/// darunter Ort und Kalender. Vergangene Termine des Tages stehen blasser da.
struct AgendaRow: View {
    let entry: Agenda.Entry
    var past = false
    /// Auf der Karte ohne Ende und ohne zweite Zeile.
    var compact = false

    var body: some View {
        let detail = Agenda.detail(entry.event)
        HStack(alignment: .top, spacing: 8) {
            CalendarBar(hex: entry.colorHex)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.time).font(RelayFont.labelLarge).monospacedDigit().foregroundStyle(RelayColor.onSurface)
                if !compact, !entry.until.isEmpty {
                    Text(entry.until).font(RelayFont.labelSmall).monospacedDigit().foregroundStyle(RelayColor.onSurfaceVariant)
                }
            }
            .frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.event.title).font(RelayFont.titleSmall).foregroundStyle(RelayColor.onSurface)
                    .lineLimit(compact ? 1 : 3).multilineTextAlignment(.leading)
                if !detail.isEmpty {
                    Text(verbatim: compact ? entry.event.calendar : detail).font(RelayFont.bodySmall)
                        .foregroundStyle(RelayColor.onSurfaceVariant).lineLimit(compact ? 1 : 2)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(past ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Kalenderkarte auf „Heute“: die Termine von heute und morgen mit der Farbe ihres Kalenders. Je Tag höchstens fünf,
/// der Rest als „n weitere“. Der Tipp auf die Karte (Knopf in TodayView) öffnet die Wochenliste. `note`: Hinweis
/// „Stand von …“ unter den Terminen, wenn der Stand nicht frisch ist (ohne Verbindung).
struct AgendaCard: View {
    let days: [Agenda.Day]
    var now = Date()
    var note: String?
    static let limit = 5

    var body: some View {
        let today = DayText.key(now)
        let clock = DayText.clock(ts: now.timeIntervalSince1970)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(days) { day in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(day.label).font(RelayFont.labelMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                        Spacer(minLength: 4)
                        if day.id == days.first?.id {
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(RelayColor.outline).accessibilityHidden(true)
                        }
                    }
                    if day.entries.isEmpty {
                        Text(day.emptyText).font(RelayFont.bodyMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                    } else {
                        ForEach(day.entries.prefix(Self.limit)) { e in
                            AgendaRow(entry: e, past: e.isPast(today: today, clock: clock), compact: true)
                        }
                        let more = Agenda.more(day.entries.count, limit: Self.limit)
                        if !more.isEmpty {
                            Text(more).font(RelayFont.labelMedium).foregroundStyle(RelayColor.primary)
                        }
                    }
                }
            }
            if let note {
                Text(verbatim: note).font(RelayFont.labelSmall).foregroundStyle(RelayColor.onSurfaceVariant)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .relayCard()
        .contentShape(Rectangle())
        .padding(.horizontal, RelaySpace.rowOuter)
    }
}

/// Wochenliste des Kalenders: oben ein Streifen mit den sieben Tagen ab heute (Tipp springt zum Tag), darunter je Tag
/// die Termine. Unten die Kalender mit ihrer Farbe und Hinweise des Gateways. Ziehen holt die Kalender frisch ab.
/// Ohne Verbindung zeigt sie den gespeicherten Stand mit „Stand von …“; Tage, die er nicht abdeckt, als „Noch nicht geladen“.
struct CalendarWeekView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var store = CalendarStore.shared
    static let count = 7

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let today = DayText.key(ctx.date)
            let clock = DayText.clock(ts: ctx.date.timeIntervalSince1970)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let feed = store.feed {
                            let days = Agenda.days(feed, from: today, count: Self.count, today: today)
                            strip(days) { day in withAnimation { proxy.scrollTo(day, anchor: .top) } }
                            let connected = model.state == .connected
                            if let stand = store.staleNote(connected: connected, now: ctx.date) {
                                note(stand, error: false).accessibilityIdentifier("calendarStale")
                            }
                            // Ohne Verbindung sagt „Stand von …“ schon alles, der Fehlertext käme nur dazu.
                            if connected, let f = store.failure { note(f, error: true) }
                            ForEach(days) { day in
                                dayBlock(day, today: today, clock: clock).id(day.date)
                            }
                            legend(feed)
                        } else if store.missing {
                            TabEmptyState(symbol: "calendar.badge.exclamationmark", title: Agenda.missingTitle,
                                          text: "Das Gateway auf dem PC kennt den Kalender nicht. Er erscheint hier, sobald das Gateway ihn anbietet.")
                                .padding(.top, 72)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("calendarMissing")
                        } else if model.state != .connected {
                            TabEmptyState(symbol: "calendar.badge.exclamationmark", title: "Kalender nicht geladen", text: Agenda.offlineEmpty)
                                .padding(.top, 72)
                        } else if let f = store.failure {
                            TabEmptyState(symbol: "calendar.badge.exclamationmark", title: "Kalender nicht geladen", text: f)
                                .padding(.top, 72)
                        } else {
                            HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 96)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .refreshable { await store.refresh(model, sync: true) }
        .navigationTitle("Kalender")
        .navigationBarTitleDisplayMode(.inline)
        .relayPage()
        .task { await store.refresh(model) }
        .onChange(of: model.state) { _, s in
            // Die Verbindung steht wieder: frisch laden, der Hinweis „Stand von …“ verschwindet.
            if s == .connected { Task { await store.refresh(model) } }
        }
        .onAppear { UsageRecorder.shared.screen("kalender") }
    }

    /// Streifen der Woche: Wochentag, Tag im Monat, darunter ein Punkt, wenn der Tag Termine hat.
    private func strip(_ days: [Agenda.Day], jump: @escaping (String) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(days) { day in
                let isToday = day.id == days.first?.id
                Button { jump(day.date) } label: {
                    VStack(spacing: 3) {
                        Text(DayText.weekday(day.date)).font(RelayFont.labelSmall)
                            .foregroundStyle(isToday ? RelayColor.onPrimaryContainer : RelayColor.onSurfaceVariant)
                        Text(DayText.dayNumber(day.date)).font(RelayFont.titleMedium).monospacedDigit()
                            .foregroundStyle(isToday ? RelayColor.onPrimaryContainer : RelayColor.onSurface)
                        Circle().fill(day.entries.isEmpty ? Color.clear : RelayColor.primary).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isToday ? RelayColor.primaryContainer : RelayColor.surfaceContainerLow,
                                in: RoundedRectangle(cornerRadius: RelayRadius.thumb, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.label), \(day.entries.count == 1 ? "1 Termin" : "\(day.entries.count) Termine")")
            }
        }
        .padding(.horizontal, RelaySpace.rowOuter)
        .padding(.top, 8)
        .accessibilityIdentifier("calendarStrip")
    }

    @ViewBuilder private func dayBlock(_ day: Agenda.Day, today: String, clock: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // „Heute“ und „Morgen“ mit dem Datum dahinter, die übrigen Tage tragen es schon im Namen.
            let long = DayText.long(day.date, today: today)
            SectionLabel(title: day.label == long ? long : "\(day.label) · \(long)")
            if day.entries.isEmpty {
                QuietLine(text: day.emptyText)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(day.entries) { e in
                        AgendaRow(entry: e, past: e.isPast(today: today, clock: clock))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .relayCard()
                .padding(.horizontal, RelaySpace.rowOuter)
            }
        }
    }

    /// Die Kalender mit Farbe, dazu Fehler einzelner Kalender und Warnungen des Gateways.
    @ViewBuilder private func legend(_ feed: CalendarFeed) -> some View {
        if !feed.sources.isEmpty {
            SectionLabel(title: "Kalender")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(feed.sources) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(s.colorHex.map { Color(hex: $0) } ?? RelayColor.primary).frame(width: 9, height: 9)
                            .accessibilityHidden(true)
                        Text(verbatim: s.label).font(RelayFont.bodyMedium).foregroundStyle(RelayColor.onSurface)
                        if !s.error.isEmpty {
                            Text(verbatim: s.error).font(RelayFont.bodySmall).foregroundStyle(RelayColor.error).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, RelaySpace.page)
        }
        ForEach(Array(feed.warnings.enumerated()), id: \.offset) { _, w in note(w, error: true) }
        note("Nur zur Ansicht. Termine änderst du im Kalender selbst.", error: false)
    }

    private func note(_ text: String, error: Bool) -> some View {
        Text(verbatim: text).font(RelayFont.bodySmall).foregroundStyle(error ? RelayColor.error : RelayColor.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RelaySpace.page).padding(.top, 10)
    }
}
