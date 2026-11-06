import SwiftUI
import RelayCore

/// The notices of the last two weeks, kept on the phone (JSON file in Application Support).
@MainActor
final class NoticeStore: ObservableObject {
    static let shared = NoticeStore()
    @Published private(set) var items: [Notice] = []

    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("notices.json")
    }

    private init() {
        if let u = Self.url, let d = try? Data(contentsOf: u), let t = String(data: d, encoding: .utf8) { items = NoticeLogic.decode(t) }
    }

    func add(_ n: Notice) {
        items = NoticeLogic.merge(items, n, now: Date().timeIntervalSince1970)
        if let u = Self.url, let d = NoticeLogic.encode(items).data(using: .utf8) { try? d.write(to: u, options: .atomic) }
    }

    func get(_ ref: String) -> Notice? { items.first { $0.ref == ref } }

    /// The answer that reached the Desktop, kept with the notice.
    func setAnswer(ref: String, _ answer: String) {
        guard let i = items.firstIndex(where: { $0.ref == ref }) else { return }
        items[i].answer = answer
        if let u = Self.url, let d = NoticeLogic.encode(items).data(using: .utf8) { try? d.write(to: u, options: .atomic) }
    }
}

/// One notice in full (links as buttons), or the list alone. Below the notice: the earlier ones.
struct NoticeView: View {
    var ref: String?
    var onOpen: (String) -> Void
    var onGo: (NoticeLogic.Goto) -> Void
    @ObservedObject private var store = NoticeStore.shared
    @Environment(\.openURL) private var openURL
    @State private var answer = ""
    @State private var answering = false
    @State private var answerError: String?

    private func when(_ ts: Double) -> String {
        Date(timeIntervalSince1970: ts).formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        let n = ref.flatMap { store.get($0) }
        let earlier = store.items.filter { $0.ref != ref }
        List {
            if ref != nil, n == nil {
                Text("Dieser Hinweis ist nicht mehr auf dem iPhone (Relay behält sie \(NoticeLogic.keepDays) Tage).").foregroundStyle(.secondary)
            }
            if let n {
                let q = Rueckfrage.question(n)
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title.isEmpty ? (q.map(Rueckfrage.title) ?? "Relay") : n.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                        Text([n.source, when(n.ts)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(NoticeLogic.lines(n.text).enumerated()), id: \.offset) { _, l in
                        if l.links.isEmpty {
                            if !l.text.isEmpty { Text(l.text).textSelection(.enabled) }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                if !l.text.isEmpty { Text(l.text).textSelection(.enabled) }
                                ForEach(l.links, id: \.self) { u in linkButton(u) }
                            }
                        }
                    }
                    let go = NoticeLogic.goto(n)
                    if go != .none {
                        Button(goLabel(go)) { onGo(go) }.buttonStyle(.bordered)
                    }
                }
                if let q, q.wantsAnswer { answerSection(n, q) }
            }
            if !earlier.isEmpty {
                Section(n != nil || ref != nil ? "Früher" : "Hinweise") {
                    ForEach(earlier.prefix(60)) { e in
                        Button { onOpen(e.ref) } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title.isEmpty ? (e.source.isEmpty ? "Relay" : e.source) : e.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(e.text.split(separator: "\n").first.map(String.init) ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Text(when(e.ts)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }.foregroundStyle(.primary)
                    }
                }
            } else if ref == nil {
                Text("Keine Hinweise in den letzten \(NoticeLogic.keepDays) Tagen.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(ref == nil ? "Hinweise" : (n?.source.isEmpty == false ? n!.source : "Hinweis"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// An agent's question: the answer goes back to the Desktop (`rueckfrage`); "Ja" takes the recommendation.
    @ViewBuilder private func answerSection(_ n: Notice, _ q: AgentQuestion) -> some View {
        Section("Antwort") {
            if let a = n.answer {
                Label("Beantwortet: \(a)", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            } else {
                TextField("Antwort an \(q.agent)", text: $answer, axis: .vertical).lineLimit(1...4)
                    .accessibilityIdentifier("questionAnswer")
                HStack(spacing: 10) {
                    if let quick = Rueckfrage.quickAnswer(q) {
                        Button("Ja (Empfehlung)") { Task { await send(n.ref, quick) } }.buttonStyle(.borderedProminent)
                    }
                    Button("Antworten") { Task { await send(n.ref, answer) } }.buttonStyle(.bordered)
                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if answering { ProgressView().controlSize(.small) }
                }.disabled(answering)
                if let e = answerError { Text(e).font(.footnote).foregroundStyle(.red) }
            }
        }
    }

    private func send(_ ref: String, _ text: String) async {
        answering = true
        defer { answering = false }
        answerError = await AppModel.shared.answerQuestion(ref: ref, text: text)
        if answerError == nil { answer = "" }
    }

    private func goLabel(_ g: NoticeLogic.Goto) -> String {
        switch g {
        case .accounts: return "Nutzung und Limits"
        case .sessions: return "Alle Sitzungen"
        case .jarvis: return "Jarvis öffnen"
        case .none: return ""
        }
    }

    @ViewBuilder private func linkButton(_ url: String) -> some View {
        if let u = URL(string: url) {
            Button { openURL(u) } label: { Label("Öffnen: \(NoticeLogic.host(url))", systemImage: "arrow.up.right.square") }
                .buttonStyle(.borderless)
        }
    }
}
