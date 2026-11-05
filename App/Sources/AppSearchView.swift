import SwiftUI
import RelayCore

/// The conversations on the Desktop (rpc `search_transcripts`): after a pause of 400 ms, one request at a time.
@MainActor
final class ContentSearcher: ObservableObject {
    @Published private(set) var hits: [ContentSearch.Hit] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var busy = false

    func update(_ raw: String, model: AppModel) {
        task?.cancel()
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ContentSearch.wanted(q), model.state == .connected else { hits = []; loading = false; error = nil; return }
        loading = true
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ContentSearch.pauseMs) * 1_000_000)
            while let self, self.busy, !Task.isCancelled { try? await Task.sleep(nanoseconds: 100_000_000) }
            guard let self, !Task.isCancelled else { return }
            self.busy = true
            defer { self.busy = false }
            do {
                let r = try await model.rpc("search_transcripts", ["query": .string(q), "days": .number(Double(ContentSearch.days))], timeout: 40)
                if !Task.isCancelled { self.hits = ContentSearch.hits(r); self.error = nil }
            } catch {
                if !Task.isCancelled { self.hits = []; self.error = error.localizedDescription }
            }
            if !Task.isCancelled { self.loading = false }
        }
    }
}

/// The extra result groups under the session list while searching: Jarvis on this phone and the conversations.
struct SearchExtras: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var searcher: ContentSearcher
    let query: String
    let openChat: (String, String) -> Void
    let openJarvis: () -> Void
    @State private var jarvisTurns: [JarvisTurn] = []

    private var q: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let jarvis = AppSearch.jarvis(jarvisTurns, query: q)
        let convs = ContentSearch.conversations(searcher.hits, sessions: Array(model.sessions.values))
        Group {
            if !jarvis.isEmpty {
                Section("Jarvis") {
                    ForEach(jarvis) { t in
                        Button(action: openJarvis) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Image(systemName: "waveform").foregroundStyle(.secondary)
                                    Text(t.q).lineLimit(1).font(.body)
                                    Spacer(minLength: 4)
                                    Text(TermText.ago(t.ts)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(AppSearch.snippet(t.a.isEmpty ? t.q : t.a, query: q)).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            if ContentSearch.wanted(q) && model.state == .connected {
                Section("In Gesprächen") {
                    ForEach(Array(convs.enumerated()), id: \.offset) { _, c in
                        Button { openChat(c.session.key, q) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(c.session.name).lineLimit(1).font(.body)
                                    Spacer(minLength: 4)
                                    Text(TermText.ago(c.hit.ts)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(c.hit.snippet).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }.buttonStyle(.plain)
                    }
                    if searcher.loading { HStack { Spacer(); ProgressView(); Spacer() } }
                    else if let e = searcher.error { Text(e).font(.footnote).foregroundStyle(.red) }
                    else if convs.isEmpty { Text("Keine Treffer in Gesprächen der letzten \(ContentSearch.days) Tage").font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .onAppear { jarvisTurns = JarvisStore.load() }
    }
}
