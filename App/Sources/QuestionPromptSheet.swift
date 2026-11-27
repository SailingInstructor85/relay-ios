import SwiftUI
import RelayCore

/// Blatt „Rückfrage jetzt“: geht beim Öffnen der App auf, wenn Rückfragen offen sind (`AppModel.offerQuestionPrompt`),
/// und zeigt die älteste mit vollem Wortlaut, Kontext und Empfehlung. „Ja (Empfehlung)“ nimmt die Empfehlung an,
/// „Antworten“ schickt den Text aus dem Feld, „Später“ schließt das Blatt bis zur nächsten neuen Rückfrage. Nach einer
/// Antwort rückt die nächste offene nach; ist keine mehr offen, schließt sich das Blatt. Die Regeln stehen in
/// `QuestionPrompt` (RelayCore), die Antwort geht über `AppModel.answerQuestion` wie in „Dein Zug“.
/// Am Antwortfeld stehen die Büroklammer und das Mikrofon wie im Jarvis-Chat (`AnswerComposer`): Das Mikrofon legt das
/// Gesprochene ins Feld, Fotos und Dokumente gehen beim Senden an den PC und stehen mit ihrem Pfad in der Antwort.
struct QuestionPromptSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var notices = NoticeStore.shared
    @State private var answer = ""
    /// Angehängte Fotos und Dokumente: Sie gehen mit der Antwort an den PC.
    @State private var docs: [JarvisDoc] = []
    @State private var progress = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var canSend: Bool { Rueckfrage.canAnswer(text: answer, docs: docs.count) }

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
        .onChange(of: open.first?.ref) { _, next in
            // die nächste Rückfrage: ihr eigener Entwurf, falls dort schon etwas getippt war (sonst leer)
            answer = next.map { DraftStore.shared.text(Drafts.question($0)) } ?? ""
            error = nil; focused = false
            docs.forEach { $0.discard() }
            docs = []
        }
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
            // Büroklammer links, Mikrofon rechts am Feld (Kennungen promptAttach, promptAnswer, promptMic)
            AnswerComposer(placeholder: "Antwort an \(q.agent)", text: $answer, docs: $docs, error: $error, focused: $focused,
                           prefix: "prompt", screen: "rückfrageblatt", draftKey: Drafts.question(n.ref))
                .disabled(sending)
            HStack(spacing: 8) {
                if let quick {
                    Button("Ja (Empfehlung)") { send(n.ref, quick) }.buttonStyle(RelayFilledButtonStyle()).accessibilityIdentifier("promptYes")
                    Button("Antworten") { send(n.ref, answer) }.buttonStyle(RelayTonalButtonStyle()).disabled(!canSend)
                        .accessibilityIdentifier("promptSend")
                } else {
                    Button("Antworten") { send(n.ref, answer) }.buttonStyle(RelayFilledButtonStyle()).disabled(!canSend)
                        .accessibilityIdentifier("promptSend")
                }
                if sending { ProgressView().controlSize(.small) }
                Spacer(minLength: 4)
                Button(QuestionPrompt.laterLabel) { model.questionPromptLater() }
                    .font(RelayFont.labelLarge).foregroundStyle(RelayColor.primary).buttonStyle(.plain)
                    .accessibilityIdentifier("promptLater")
            }
            .disabled(sending)
            if !progress.isEmpty { Text(progress).font(RelayFont.bodySmall).foregroundStyle(RelayColor.onSurfaceVariant) }
            if let error { Text(error).font(RelayFont.bodySmall).foregroundStyle(RelayColor.error) }
        }
        .padding(.horizontal, RelaySpace.page).padding(.vertical, 12)
        .background(RelayColor.surfaceContainer)
    }

    /// Anhänge gehen zuerst an den PC, ihre Pfade stehen dann am Ende der Antwort. Scheitert das Hochladen, bleibt
    /// alles stehen. Scheitert danach die Antwort, steht sie mit den Pfaden im Feld und nichts wird doppelt hochgeladen.
    private func send(_ ref: String, _ text: String) {
        sending = true
        error = nil
        let batch = docs
        UsageRecorder.shared.record("rückfrageblatt", "rückfrage beantwortet", kind: batch.isEmpty ? "text" : "datei", length: text.count)
        Task { @MainActor in
            var body = text
            if !batch.isEmpty {
                do {
                    let paths = try await DocIntake.upload(batch, model: model) { progress = $0 }
                    progress = ""
                    body = Rueckfrage.answerBody(text, paths: paths)
                    batch.forEach { $0.discard() }
                    docs.removeAll { d in batch.contains { $0.id == d.id } }
                    answer = body
                } catch {
                    progress = ""
                    sending = false
                    self.error = "Anhang nicht hochgeladen: \(error.localizedDescription)"
                    return
                }
            }
            let e = await model.answerQuestion(ref: ref, text: body)
            sending = false
            // ist die Rückfrage inzwischen zu (auch durch eine Antwort von woanders), zeigt das Blatt schon die nächste
            if NoticeStore.shared.get(ref)?.answer == nil { error = e }
        }
    }
}
