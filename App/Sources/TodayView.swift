import SwiftUI
import RelayCore

/// Tab „Heute“: die Übersicht des Tages wie „Today“ der Android-App. Von oben: Kopfzeile mit Pille und Kennzahlen,
/// Abschnitt „Braucht dich“ (kompakt, die Karten stehen in „Dein Zug“), Assistent-Karte, Kalenderkarte (erst mit
/// Daten sichtbar), Abschnitt „Sitzungen“. Unten schwebt die Eingabeleiste für den Assistenten.
struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var approvals = Approvals.shared
    @ObservedObject private var notices = NoticeStore.shared
    @State private var jarvisTurns: [JarvisTurn] = []
    @State private var ask = ""
    @State private var showNew = false
    @FocusState private var askFocused: Bool

    /// Termine des Tages. Die Quelle (Gateway, rpc `calendar`) kommt mit einem späteren Paket; solange die Liste
    /// leer ist, erscheint keine Kalenderkarte.
    private var agenda: [Today.AgendaItem] { [] }

    private func push(_ r: Route) { router.push(r, in: .today) }

    var body: some View {
        // Altersangaben zählen weiter, auch wenn kein Ereignis kommt.
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date
            let turn = YourTurnData.items(model, now: now.timeIntervalSince1970)
            let rows = Today.rows(Array(model.sessions.values), unread: model.unread, pinned: model.pinned, hidden: model.hidden)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusStrip(waiting: turn.count, now: now)
                    connectionBanner
                    ErrorBanner(text: $model.lastError)
                    needsSection(turn)
                    assistantCard(now)
                    if !agenda.isEmpty {
                        SectionLabel(title: "Kalender")
                        AgendaCard(items: agenda)
                    }
                    sessionsSection(rows, now: now)
                }
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refresh() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .relayRootTitle(AppTab.today.title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ConnDot()
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .disabled(model.state != .connected)
                    .accessibilityLabel("Neue Sitzung").accessibilityIdentifier("todayNew")
            }
        }
        .task { await model.pollTriage() }
        .onAppear {
            UsageRecorder.shared.screen("heute")
            jarvisTurns = JarvisStore.load()
        }
        .sheet(isPresented: $showNew) {
            NewSessionView { target in
                showNew = false
                Task { @MainActor in // der Platzhalter der neuen Sitzung erscheint kurz nach dem Start
                    for _ in 0..<20 {
                        if let s = model.session(for: "tmux:\(target)") { push(.chat(s.key)); return }
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await model.refresh()
                    }
                }
            }.environmentObject(model)
        }
    }

    // MARK: Kopfzeile

    /// Pille „n brauchen dich“ oder „n ungelesen“, dahinter RAM, CPU und die Kontingente der Konten (wie der Streifen
    /// über der Sitzungsliste). Ohne Inhalt entfällt die Zeile.
    @ViewBuilder private func statusStrip(waiting: Int, now: Date) -> some View {
        let offline = model.state != .connected
        let pill = Today.pill(waiting: waiting, unread: Triage.counts(model.triageSessions, unread: model.unread).unread)
        let ram = offline ? nil : Triage.ram(model.memory)
        let cpu = offline ? nil : Triage.cpu(model.memory)
        let quotas = offline ? [] : Triage.quota(model.usage)
        let stale = offline ? Triage.staleText(lastSync: model.lastSync, now: now) : ""
        if pill != nil || ram != nil || cpu != nil || !quotas.isEmpty || !stale.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let pill {
                        Button { pillTapped(pill) } label: {
                            RelayPill(text: pill.text + " ›",
                                      fill: pill.urgent ? RelayColor.errorContainer : RelayColor.secondaryContainer,
                                      color: pill.urgent ? RelayColor.onErrorContainer : RelayColor.onSecondaryContainer)
                        }
                        .accessibilityIdentifier("todayPill")
                    }
                    if !stale.isEmpty {
                        Text(stale).font(RelayFont.labelMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                    }
                    if let r = ram {
                        Button { push(.memory) } label: {
                            Text("RAM \(r.text)").font(RelayFont.labelLarge).foregroundStyle(RelayColor.level(r.level))
                        }
                    }
                    if let c = cpu {
                        Button { push(.memory) } label: {
                            Text(c.text).font(RelayFont.labelMedium).foregroundStyle(RelayColor.level(c.level))
                        }
                    }
                    ForEach(quotas) { q in
                        Button { push(.usage) } label: {
                            HStack(spacing: 4) {
                                Text("\(q.alias) \(q.text)").foregroundStyle(RelayColor.level(q.level))
                                if !q.week.isEmpty { Text(q.week).foregroundStyle(RelayColor.level(q.weekLevel)) }
                            }
                            .font(RelayFont.labelMedium)
                            .padding(.horizontal, 10)
                            .frame(minHeight: RelaySpace.pillHeight)
                            .background(RelayColor.surfaceContainerLow, in: Capsule())
                        }
                    }
                }
                .monospacedDigit()
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 6)
        }
    }

    /// Wer wartet, steht in „Dein Zug“; bei nur Ungelesenem öffnet die Pille die nächste ungelesene Sitzung.
    private func pillTapped(_ pill: Today.Pill) {
        if pill.urgent { router.show(.yourTurn); return }
        if let n = Triage.next(model.triageSessions, unread: model.unread) { push(.chat(n.key)) }
    }

    /// Nur ohne Verbindung: Zustand in einem Satz, daneben „Erneut“.
    @ViewBuilder private var connectionBanner: some View {
        if model.state != .connected {
            HStack(spacing: 8) {
                if model.state == .connecting { ProgressView().controlSize(.small) }
                Text(model.connLabel).font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant).lineLimit(2)
                Spacer(minLength: 8)
                Button("Erneut") { model.reconnect() }.font(RelayFont.labelMedium).foregroundStyle(RelayColor.primary).buttonStyle(.plain)
            }
            .padding(.horizontal, RelaySpace.page).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RelayColor.surfaceVariant)
        }
    }

    // MARK: Braucht dich

    @ViewBuilder private func needsSection(_ items: [YourTurn.Item]) -> some View {
        SectionLabel(title: "Braucht dich", count: items.count)
        if items.isEmpty {
            QuietLine(text: YourTurn.empty)
        } else {
            let needs = Today.needs(items)
            Button { router.show(.yourTurn) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(needs.shown) { n in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(n.label).font(RelayFont.labelSmall).foregroundStyle(RelayColor.error)
                                Text(n.title).font(RelayFont.titleSmall).foregroundStyle(RelayColor.onSurface).lineLimit(1)
                                Spacer(minLength: 4)
                                if n.since > 0 {
                                    Text(TermText.ago(n.since)).font(RelayFont.labelMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                                }
                            }
                            if !n.text.isEmpty {
                                Text(n.text).font(RelayFont.bodyMedium).foregroundStyle(RelayColor.onSurfaceVariant).lineLimit(1)
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        Text(Today.needsLink(more: needs.more)).font(RelayFont.labelLarge)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(RelayColor.primary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .relayCard(RelayColor.waitingTint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, RelaySpace.rowOuter)
            .accessibilityIdentifier("todayNeeds")
        }
    }

    // MARK: Assistent

    /// Karte des Assistenten: Name in Serif, rechts das Alter der letzten Antwort, darunter die letzte Antwort
    /// (höchstens drei Zeilen). Ein Tipp öffnet Jarvis.
    private func assistantCard(_ now: Date) -> some View {
        let last = Today.assistantLast(jarvisTurns)
        return Button { push(.jarvis) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").font(.system(size: 14, weight: .semibold)).foregroundStyle(RelayColor.onPrimary)
                        .frame(width: 32, height: 32)
                        .background(RelayColor.primary, in: Circle())
                        .accessibilityHidden(true)
                    Text(Today.assistantName).font(RelayFont.titleMedium).foregroundStyle(RelayColor.onSurface)
                    Spacer(minLength: 4)
                    if last > 0 {
                        Text(TermText.ago(last, now: now)).font(RelayFont.labelMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                    }
                }
                Text(Today.assistantPreview(jarvisTurns)).font(RelayFont.bodyMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                    .lineLimit(3).multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .relayCard(RelayColor.surfaceContainerLow, radius: RelayRadius.hero)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, RelaySpace.rowOuter)
        .padding(.top, 14)
        .accessibilityIdentifier("assistantCard")
    }

    // MARK: Sitzungen

    @ViewBuilder private func sessionsSection(_ rows: [Today.Row], now: Date) -> some View {
        let stale = model.state != .connected
        SectionLabel(title: "Sitzungen")
        if rows.isEmpty {
            QuietLine(text: stale ? "Sitzungen erscheinen, sobald der PC erreichbar ist." : "Keine laufenden Sitzungen.")
        } else {
            VStack(spacing: 2) {
                ForEach(rows) { row in
                    Button {
                        UsageRecorder.shared.record("heute", "chat geöffnet", session: row.key)
                        push(.chat(row.key))
                    } label: {
                        SessionCard(row: row, look: model.look, stale: stale, now: now)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        Button { router.show(.sessions) } label: {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet").font(.system(size: 15)).foregroundStyle(RelayColor.onSurfaceVariant).frame(width: 28)
                    .accessibilityHidden(true)
                Text("Alle Sitzungen").font(RelayFont.titleSmall).foregroundStyle(RelayColor.onSurface)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(RelayColor.outline)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: RelaySpace.optionMinHeight)
            .relayCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, RelaySpace.rowOuter)
        .padding(.top, 10)
        .accessibilityIdentifier("todayAllSessions")
    }

    // MARK: Eingabeleiste

    /// Schwebende Eingabeleiste: Kapsel auf einer Fläche in der Farbe der Tab-Leiste. Links das Mikrofon (Jarvis per
    /// Sprache), rechts Senden. Der Text geht als Frage an Jarvis, die Antwort erscheint in dessen Ansicht.
    private var composer: some View {
        let text = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(alignment: .center, spacing: 2) {
            Button { askFocused = false; push(.jarvisListening) } label: {
                Image(systemName: "mic.fill").font(.system(size: 17)).foregroundStyle(RelayColor.primary)
                    .frame(width: RelaySpace.barButton, height: RelaySpace.barButton)
            }
            .accessibilityLabel("Jarvis per Sprache").accessibilityIdentifier("todayMic")
            TextField(Today.assistantPlaceholder, text: $ask)
                .font(RelayFont.bodyLarge)
                .foregroundStyle(RelayColor.onSurface)
                .focused($askFocused)
                .submitLabel(.send)
                .onSubmit { sendAsk() }
                .accessibilityIdentifier("todayInput")
            Button { sendAsk() } label: {
                Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(RelayColor.onPrimary)
                    .frame(width: RelaySpace.barButton, height: RelaySpace.barButton)
                    .background(RelayColor.primary.opacity(text.isEmpty ? 0.3 : 1), in: Circle())
            }
            .disabled(text.isEmpty)
            .accessibilityLabel("Senden").accessibilityIdentifier("todaySend")
        }
        .buttonStyle(.plain)
        .padding(.leading, 4).padding(.trailing, 6).padding(.vertical, 4)
        .background(RelayColor.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: RelayRadius.composer, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: RelayRadius.composer, style: .continuous).strokeBorder(RelayColor.outlineVariant, lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(RelayColor.surfaceContainer)
    }

    private func sendAsk() {
        let q = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        ask = ""
        askFocused = false
        UsageRecorder.shared.record("heute", "jarvis gefragt", kind: "text", length: q.count)
        push(.jarvisAsk(q))
    }
}

/// Kalenderkarte auf „Heute“: Zeit und Titel je Termin. Wird nur mit Einträgen gezeigt.
struct AgendaCard: View {
    let items: [Today.AgendaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Today.agendaTime(item)).font(RelayFont.labelLarge).monospacedDigit().foregroundStyle(RelayColor.primary)
                        .frame(minWidth: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(RelayFont.titleSmall).foregroundStyle(RelayColor.onSurface).lineLimit(2)
                        if !item.location.isEmpty {
                            Text(item.location).font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant).lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .relayCard()
        .padding(.horizontal, RelaySpace.rowOuter)
    }
}
