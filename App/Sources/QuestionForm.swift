import SwiftUI
import RelayCore

/// The agent's AskUserQuestion as a form at the bottom of the chat: header chips, every question with its options.
/// A single-select lone question answers with one tap; a multi-select question or a form collects a choice per question
/// and submits them together; "Etwas anderes..." opens a text field. The whole answer goes in one `send` with `steps`
/// and `expect_question`, so a stale card can never answer a newer question (the gateway refuses it, the card reloads).
struct QuestionFormCard: View {
    @EnvironmentObject var model: AppModel
    let q: Question
    let session: Session
    let onSent: () async -> Void

    @State private var picks: [Pick]
    @State private var sending = false
    @State private var error: String?

    init(q: Question, session: Session, onSent: @escaping () async -> Void) {
        self.q = q; self.session = session; self.onSent = onSent
        _picks = State(initialValue: Array(repeating: Pick(), count: q.all.count))
    }

    private var form: [Question] { q.all }
    private var oneTap: Bool { AnswerKeys.usable(q) }
    private var canType: Bool { AnswerKeys.formUsable(q) }
    private var interactive: Bool { oneTap || canType }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(Array(form.enumerated()), id: \.offset) { qi, f in
                if qi > 0 { Divider() }
                Text(f.text).font(.headline)
                if f.multi { Text("Eine oder mehrere wählen").font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(f.options.enumerated()), id: \.offset) { i, o in
                    optionRow(label: o.label, description: o.description, selected: picks[qi].options.contains(i), multi: f.multi) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if oneTap { Task { await sendOne(i) } } else { picks[qi] = picks[qi].choose(i, multi: f.multi) }
                    }
                }
                if canType {
                    let open = picks[qi].other != nil
                    optionRow(label: "Etwas anderes…", description: "", selected: open, multi: f.multi) {
                        picks[qi] = picks[qi].typing(multi: f.multi)
                    }
                    if open {
                        TextField("Deine Antwort", text: Binding(get: { picks[qi].other ?? "" }, set: { picks[qi].other = $0 }), axis: .vertical)
                            .lineLimit(1...4).textFieldStyle(.roundedBorder)
                    }
                }
            }
            let more = q.count - form.count // an older gateway sends only the first question of a form
            if more > 0 { Text("+ \(more) weitere Frage\(more > 1 ? "n" : "")").font(.caption).foregroundStyle(.secondary) }
            if !interactive {
                Text("Diese Frage lässt sich hier nicht beantworten. Öffne den Live-Bildschirm oder lehne ab.").font(.caption).foregroundStyle(.secondary)
            }
            let left = form.indices.filter { !AnswerKeys.answered(form[$0], picks[$0]) }.count
            if interactive && !oneTap && left > 0 && form.count > 1 {
                Text("noch \(left) Frage\(left > 1 ? "n" : "") offen").font(.caption).foregroundStyle(.secondary)
            }
            if let e = error { Text(e).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Ablehnen", role: .destructive) { Task { await decline() } }.disabled(sending)
                Spacer()
                if sending { ProgressView() }
                else if interactive && (!oneTap || picks.first?.other != nil) {
                    Button(form.count > 1 ? "Antworten senden" : "Absenden") { Task { await submit() } }
                        .buttonStyle(.borderedProminent).disabled(!ready)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.35)))
        .padding(.horizontal)
        .disabled(sending)
    }

    private var ready: Bool { form.indices.allSatisfy { AnswerKeys.answered(form[$0], picks[$0]) } }

    @ViewBuilder private var header: some View {
        HStack(spacing: 6) {
            Label(form.count > 1 ? "Claude fragt \(form.count) Dinge" : "Claude fragt", systemImage: "questionmark.bubble")
                .font(.subheadline.weight(.semibold))
            if form.count > 1 || !(form.first?.header.isEmpty ?? true) {
                ForEach(Array(form.enumerated()), id: \.offset) { i, f in
                    let done = form.count > 1 && AnswerKeys.answered(f, picks[i])
                    HStack(spacing: 2) {
                        if done { Image(systemName: "checkmark").font(.caption2) }
                        Text(f.header.isEmpty ? "\(i + 1)" : f.header).font(.caption).lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(done ? Color.green.opacity(0.25) : Color.secondary.opacity(0.18), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            SpeakQuestionButton { SpeechOut.shared.speak(ReadAloud.spoken(question: q)) }
        }
    }

    private func optionRow(label: String, description: String, selected: Bool, multi: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                if !oneTap {
                    Image(systemName: multi ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle"))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.callout).multilineTextAlignment(.leading)
                    if !description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 0)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected && !oneTap ? Color.accentColor.opacity(0.6) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sendOne(_ i: Int) async {
        await go(AnswerKeys.sendParams(key: session.key, index: i, question: q.text))
    }

    private func submit() async {
        guard let p = AnswerKeys.stepsParams(key: session.key, question: q, picks: picks) else { return }
        await go(p)
    }

    private func decline() async {
        await go(AnswerKeys.declineParams(key: session.key, question: q))
    }

    private func go(_ params: JSON) async {
        sending = true; defer { sending = false }
        do {
            try await model.answer(params)
            error = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
        } catch {
            self.error = error.localizedDescription
            await model.refresh() // a refused answer: the question may have changed, reload the card
        }
        await onSent()
    }
}
