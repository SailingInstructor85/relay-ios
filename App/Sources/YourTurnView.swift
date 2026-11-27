import SwiftUI
import RelayCore

/// Die Einträge für „Dein Zug“ aus dem Zustand der App (Modell, Freigaben, Hinweise). Die Regeln stehen in
/// `YourTurn` (RelayCore).
@MainActor
enum YourTurnData {
    static func items(_ model: AppModel, now: Double = Date().timeIntervalSince1970) -> [YourTurn.Item] {
        YourTurn.items(sessions: model.triageSessions, notices: NoticeStore.shared.items, requests: Approvals.shared.requests,
                       confirms: Approvals.shared.confirms, cloud: model.cloudSessions, now: now)
    }
}

/// Tab „Dein Zug“: je Eintrag eine Karte, das Älteste zuerst. Rückfragen, Freigaben und Bestätigungen lassen sich
/// direkt auf der Karte beantworten, wartende Sitzungen öffnen den Chat, Cloud-Sitzungen die Claude-App.
struct YourTurnView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var approvals = Approvals.shared
    @ObservedObject private var notices = NoticeStore.shared

    private func push(_ r: Route) { router.push(r, in: .yourTurn) }

    var body: some View {
        // Alter und Ablauf der Einträge zählen weiter, auch wenn kein Ereignis kommt.
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let items = YourTurnData.items(model, now: ctx.date.timeIntervalSince1970)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if model.state != .connected {
                        QuietLine(text: [model.connLabel, Triage.staleText(lastSync: model.lastSync, now: ctx.date)]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                    if items.isEmpty {
                        TabEmptyState(symbol: "checkmark.circle", title: YourTurn.empty,
                                      text: "Rückfragen, Freigaben und wartende Sitzungen erscheinen hier.")
                            .padding(.top, 120)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("yourTurnEmpty")
                    }
                    ForEach(items) { item in card(item) }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refresh(); await model.loadCloud() }
        }
        .relayRootTitle(AppTab.yourTurn.title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !DriveQueue.open(notices.items).isEmpty {
                    Button { push(.drive) } label: { Image(systemName: "car") }
                        .accessibilityLabel("Sprachmodus").accessibilityIdentifier("turnDrive")
                }
                Button { push(.notices) } label: { Image(systemName: "bell") }
                    .accessibilityLabel("Hinweise").accessibilityIdentifier("turnNotices")
                ConnDot()
            }
        }
        .onAppear { UsageRecorder.shared.screen("deinzug") }
    }

    @ViewBuilder private func card(_ item: YourTurn.Item) -> some View {
        switch item.target {
        case .session(let key):
            SessionTurnCard(item: item, session: model.session(for: key), open: {
                UsageRecorder.shared.record("deinzug", "chat geöffnet", session: key)
                push(.chat(key))
            })
        case .question(let ref, let agent, let quick):
            QuestionTurnCard(item: item, ref: ref, agent: agent, quick: quick, openFull: { push(.notice(ref)) })
        case .approval(let newest, let all):
            DecisionTurnCard(item: item, yes: "Freigeben",
                             onYes: { UsageRecorder.shared.record("deinzug", "freigabe", detail: "ja"); await approvals.decide([newest], ok: true) },
                             onNo: { UsageRecorder.shared.record("deinzug", "freigabe", detail: "nein"); await approvals.decide(all, ok: false) })
        case .confirm(let id):
            DecisionTurnCard(item: item, yes: "Bestätigen",
                             onYes: { UsageRecorder.shared.record("deinzug", "bestätigung", detail: "ja"); await approvals.confirm(id, ok: true) },
                             onNo: { UsageRecorder.shared.record("deinzug", "bestätigung", detail: "nein"); await approvals.confirm(id, ok: false) })
        case .cloud(let url):
            CloudTurnCard(item: item, url: url)
        }
    }
}

/// Die gemeinsame Kartenform: getönte Fläche, links Avatar oder Symbol der Art, Titel in Serif, rechts das Alter,
/// darunter Art und Herkunft, dann der Inhalt der Karte.
struct TurnCard<Content: View>: View {
    let item: YourTurn.Item
    var session: Session?
    var look = Avatars.Look()
    @ViewBuilder var content: () -> Content

    private var symbol: String {
        switch item.kind {
        case .approval: return "checkmark.seal.fill"
        case .confirm: return "hand.raised.fill"
        case .question: return "questionmark.bubble.fill"
        case .session: return "terminal.fill"
        case .cloud: return "cloud.fill"
        }
    }

    private var meta: String {
        [YourTurn.kindLabel(item.kind), item.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RelaySpace.cardGap) {
            HStack(alignment: .top, spacing: 10) {
                if let s = session {
                    SessionAvatar(s: s, unread: false, stale: false, look: look)
                } else {
                    Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(RelayColor.onErrorContainer)
                        .frame(width: 38, height: 38)
                        .background(RelayColor.errorContainer, in: Circle())
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.title).font(RelayFont.titleMedium).foregroundStyle(RelayColor.onSurface).lineLimit(2)
                        Spacer(minLength: 4)
                        if item.since > 0 {
                            Text(TermText.ago(item.since)).font(RelayFont.labelMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                        }
                    }
                    Text(meta).font(RelayFont.labelSmall).foregroundStyle(RelayColor.error).lineLimit(1)
                }
            }
            content()
        }
        .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .relayCard(RelayColor.waitingTint)
        .padding(.horizontal, RelaySpace.rowOuter)
    }
}

/// Text einer Karte mit Vorsatz („Kontext“, „Empfehlung“).
private struct LabeledText: View {
    let label: String
    let text: String
    var lines = 4

    var body: some View {
        (Text(label + ": ").fontWeight(.semibold) + Text(text))
            .font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant).lineLimit(lines)
    }
}

/// Wartende Sitzung: Frage oder letzte Nachricht, „Chat öffnen“ und „Erledigt“. Ein Tipp auf die Karte öffnet den Chat.
struct SessionTurnCard: View {
    @EnvironmentObject var model: AppModel
    let item: YourTurn.Item
    let session: Session?
    let open: () -> Void

    var body: some View {
        TurnCard(item: item, session: session, look: model.look) {
            if !item.text.isEmpty {
                Text(item.text).font(RelayFont.bodyLarge).foregroundStyle(RelayColor.onSurface).lineLimit(6)
            }
            HStack(spacing: 8) {
                Button("Chat öffnen", action: open).buttonStyle(RelayFilledButtonStyle()).accessibilityIdentifier("turnOpenChat")
                if let s = session {
                    Button("Erledigt") {
                        UsageRecorder.shared.record("deinzug", "erledigt", session: s.key)
                        Task { @MainActor in await model.done(s) }
                    }
                    .buttonStyle(RelayTonalButtonStyle())
                }
            }
            .padding(.top, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}

/// Rückfrage eines Agenten: Frage, Kontext, Empfehlung, Antwortfeld. „Ja (Empfehlung)“ nimmt die Empfehlung an,
/// „Erledigt“ schließt sie ohne Bearbeiten (Antwort „(verworfen)“, nach Nachfrage).
/// Die Antwort geht über dieselbe Stelle wie in den Hinweisen (`AppModel.answerQuestion`).
struct QuestionTurnCard: View {
    let item: YourTurn.Item
    let ref: String
    let agent: String
    let quick: String?
    let openFull: () -> Void
    @State private var answer = ""
    @State private var sending = false
    @State private var error: String?
    @State private var confirmDismiss = false
    @FocusState private var focused: Bool

    private var trimmed: String { answer.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        TurnCard(item: item) {
            Text(item.text).font(RelayFont.bodyLarge).foregroundStyle(RelayColor.onSurface).lineLimit(8)
            if !item.context.isEmpty { LabeledText(label: "Kontext", text: item.context) }
            if !item.recommendation.isEmpty { LabeledText(label: "Empfehlung", text: item.recommendation) }
            TextField("Antwort an \(agent)", text: $answer, axis: .vertical).lineLimit(1...4)
                .font(RelayFont.bodyLarge)
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RelayColor.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: RelayRadius.option, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: RelayRadius.option, style: .continuous).strokeBorder(RelayColor.outlineVariant, lineWidth: 1) }
                .accessibilityIdentifier("turnAnswer")
                .padding(.top, 2)
                // der Entwurf der Antwort übersteht Absturz und Beenden der App, je Rückfrage (`Drafts`)
                .keepsDraft(Drafts.question(ref), text: $answer)
            HStack(spacing: 8) {
                if let quick {
                    Button("Ja (Empfehlung)") { send(quick) }.buttonStyle(RelayFilledButtonStyle()).accessibilityIdentifier("turnYes")
                    Button("Antworten") { send(answer) }.buttonStyle(RelayTonalButtonStyle()).disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("turnSend")
                } else {
                    Button("Antworten") { send(answer) }.buttonStyle(RelayFilledButtonStyle()).disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("turnSend")
                }
                if sending { ProgressView().controlSize(.small) }
            }
            .disabled(sending)
            // zweite, kleine Zeile: ganz lesen, und die Rückfrage ohne Antwort schließen (nach Nachfrage)
            HStack(spacing: 8) {
                Button("Ganz lesen", action: openFull).font(RelayFont.labelLarge).foregroundStyle(RelayColor.primary).buttonStyle(.plain)
                Spacer(minLength: 4)
                Button(Rueckfrage.dismissLabel) { confirmDismiss = true }
                    .font(RelayFont.labelLarge).foregroundStyle(RelayColor.onSurfaceVariant).buttonStyle(.plain)
                    .accessibilityIdentifier("turnDismiss")
            }
            .disabled(sending)
            .confirmationDialog(Rueckfrage.dismissTitle, isPresented: $confirmDismiss, titleVisibility: .visible) {
                Button(Rueckfrage.dismissConfirm, role: .destructive) { send(Rueckfrage.dismissed, dismiss: true) }
                Button("Abbrechen", role: .cancel) {}
            } message: { Text(Rueckfrage.dismissNote(agent: agent)) }
            if let error { Text(error).font(RelayFont.bodySmall).foregroundStyle(RelayColor.error) }
        }
    }

    private func send(_ text: String, dismiss: Bool = false) {
        sending = true
        UsageRecorder.shared.record("deinzug", dismiss ? "rückfrage verworfen" : "rückfrage beantwortet", kind: "text", length: text.count)
        Task { @MainActor in
            let e = await AppModel.shared.answerQuestion(ref: ref, text: text)
            sending = false
            error = e
            if e == nil { answer = ""; focused = false }
        }
    }
}

/// Freigabe des Desktops oder Bestätigung für Jarvis: der genaue Wortlaut, dann Ja und „Ablehnen“.
struct DecisionTurnCard: View {
    let item: YourTurn.Item
    let yes: String
    let onYes: @MainActor () async -> Void
    let onNo: @MainActor () async -> Void
    @State private var busy = false

    var body: some View {
        TurnCard(item: item) {
            Text(item.text).font(RelayFont.bodyLarge).foregroundStyle(RelayColor.onSurface).textSelection(.enabled)
            if item.expiresAt > 0 {
                Text("Läuft ab \(Date(timeIntervalSince1970: item.expiresAt).formatted(date: .omitted, time: .shortened))")
                    .font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant)
            }
            if let note = YourTurn.repeatsNote(item.repeats) {
                Text(note).font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant)
            }
            HStack(spacing: 8) {
                Button(yes) { run(onYes) }.buttonStyle(RelayFilledButtonStyle()).accessibilityIdentifier("turnApprove")
                Button("Ablehnen") { run(onNo) }.buttonStyle(RelayTonalButtonStyle(destructive: true)).accessibilityIdentifier("turnDeny")
                if busy { ProgressView().controlSize(.small) }
            }
            .disabled(busy)
            .padding(.top, 2)
        }
    }

    private func run(_ f: @escaping @MainActor () async -> Void) {
        busy = true
        Task { @MainActor in await f(); busy = false }
    }
}

/// Wartende Cloud-Sitzung (claude.ai/code): öffnet die Adresse in der Claude-App oder im Browser.
struct CloudTurnCard: View {
    let item: YourTurn.Item
    let url: String

    var body: some View {
        TurnCard(item: item) {
            if !item.text.isEmpty {
                Text(item.text).font(RelayFont.bodyLarge).foregroundStyle(RelayColor.onSurface).lineLimit(6)
            }
            if let u = URL(string: url), !url.isEmpty {
                Button("In Claude öffnen") { UIApplication.shared.open(u) }.buttonStyle(RelayFilledButtonStyle()).padding(.top, 2)
            }
        }
    }
}
