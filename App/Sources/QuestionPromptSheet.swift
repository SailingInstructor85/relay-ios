import SwiftUI
import RelayCore

/// Blatt „Rückfrage jetzt“: geht beim Öffnen der App auf, wenn Rückfragen offen sind (`AppModel.offerQuestionPrompt`),
/// und zeigt die älteste mit vollem Wortlaut, Kontext und Empfehlung. „Ja (Empfehlung)“ nimmt die Empfehlung an,
/// „Antworten“ schickt den Text aus dem Feld, „Später“ schließt das Blatt bis zur nächsten neuen Rückfrage. Nach einer
/// Antwort rückt die nächste offene nach; ist keine mehr offen, schließt sich das Blatt. Die Regeln stehen in
/// `QuestionPrompt` (RelayCore), die Antwort geht über `AppModel.answerQuestion` wie in „Dein Zug“.
struct QuestionPromptSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var notices = NoticeStore.shared
    @State private var answer = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { answer.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let open = QuestionPrompt.open(notices.items)
        Group {
            if let n = open.first, let q = Rueckfrage.question(n) {
                page(n, q, count: open.count)
            } else {
                // alles beantwortet (hier oder woanders): nichts mehr zu zeigen
                Color.clear.onAppear { model.showQuestionPrompt = false }
            }
        }
        .background(RelayColor.background.ignoresSafeArea())
        .onChange(of: open.first?.ref) { _, _ in answer = ""; error = nil; focused = false }
        .onChange(of: open.isEmpty) { _, empty in if empty { model.showQuestionPrompt = false } }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func page(_ n: Notice, _ q: AgentQuestion, count: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(QuestionPrompt.countLabel(count)).font(RelayFont.labelLarge).foregroundStyle(RelayColor.error)
                    .accessibilityIdentifier("promptCount")
                Text(n.title.isEmpty ? Rueckfrage.title(q) : n.title).font(RelayFont.headline).foregroundStyle(RelayColor.onSurface)
                Text([q.agent, n.ts > 0 ? TermText.ago(n.ts) : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(RelayFont.labelMedium).foregroundStyle(RelayColor.onSurfaceVariant)
                Text(q.question).font(RelayFont.bodyLarge).foregroundStyle(RelayColor.onSurface).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !q.context.isEmpty { block("Kontext", q.context) }
                if !q.recommendation.isEmpty { block("Empfehlung", q.recommendation) }
            }
            .padding(.horizontal, RelaySpace.page).padding(.top, 28).padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { answerBar(n, q) }
    }

    private func block(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(RelayFont.labelLarge).foregroundStyle(RelayColor.onSurfaceVariant)
            Text(text).font(RelayFont.bodyLarge).foregroundStyle(RelayColor.onSurface).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Antwortfeld und die drei Knöpfe, fest am unteren Rand (auch bei langem Wortlaut immer erreichbar).
    private func answerBar(_ n: Notice, _ q: AgentQuestion) -> some View {
        let quick = Rueckfrage.quickAnswer(q)
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Antwort an \(q.agent)", text: $answer, axis: .vertical).lineLimit(1...4)
                .font(RelayFont.bodyLarge)
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RelayColor.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: RelayRadius.option, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: RelayRadius.option, style: .continuous).strokeBorder(RelayColor.outlineVariant, lineWidth: 1) }
                .accessibilityIdentifier("promptAnswer")
            HStack(spacing: 8) {
                if let quick {
                    Button("Ja (Empfehlung)") { send(n.ref, quick) }.buttonStyle(RelayFilledButtonStyle()).accessibilityIdentifier("promptYes")
                    Button("Antworten") { send(n.ref, answer) }.buttonStyle(RelayTonalButtonStyle()).disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("promptSend")
                } else {
                    Button("Antworten") { send(n.ref, answer) }.buttonStyle(RelayFilledButtonStyle()).disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("promptSend")
                }
                if sending { ProgressView().controlSize(.small) }
                Spacer(minLength: 4)
                Button(QuestionPrompt.laterLabel) { model.questionPromptLater() }
                    .font(RelayFont.labelLarge).foregroundStyle(RelayColor.primary).buttonStyle(.plain)
                    .accessibilityIdentifier("promptLater")
            }
            .disabled(sending)
            if let error { Text(error).font(RelayFont.bodySmall).foregroundStyle(RelayColor.error) }
        }
        .padding(.horizontal, RelaySpace.page).padding(.vertical, 12)
        .background(RelayColor.surfaceContainer)
    }

    private func send(_ ref: String, _ text: String) {
        sending = true
        UsageRecorder.shared.record("rückfrageblatt", "rückfrage beantwortet", kind: "text", length: text.count)
        Task { @MainActor in
            let e = await model.answerQuestion(ref: ref, text: text)
            sending = false
            // ist die Rückfrage inzwischen zu (auch durch eine Antwort von woanders), zeigt das Blatt schon die nächste
            if NoticeStore.shared.get(ref)?.answer == nil { error = e }
        }
    }
}
