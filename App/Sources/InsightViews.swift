import SwiftUI
import RelayCore

/// "Was war los": rpc `digest` (finished, waiting, closed sessions in the last hours).
struct DigestView: View {
    @EnvironmentObject var model: AppModel
    @State private var hours = 12.0
    @State private var data: JSON = .null
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Picker("Zeitraum", selection: $hours) {
                    Text("30 Min.").tag(0.5); Text("2 Std.").tag(2.0); Text("12 Std.").tag(12.0); Text("24 Std.").tag(24.0)
                    Text("3 Tage").tag(72.0); Text("7 Tage").tag(168.0)
                }.pickerStyle(.menu)
            }
            if let e = error { Text(e).foregroundStyle(.red).font(.footnote) }
            if !data.isNull {
                let d = data["data"]
                if !data.str("title").isEmpty || !data.str("text").isEmpty {
                    Section(data.str("title", "Zusammenfassung")) { Text(data.str("text")).font(.callout) }
                }
                list("Fertig", d["finished"].array) { s in
                    row(s, sub: s.str("last_message"), at: s.num("at"))
                }
                list("Wartet", d["waiting"].array) { s in
                    row(s, sub: s.str("question"), at: s.num("since"))
                }
                list("Geschlossen", d["closed"].array) { s in
                    row(s, sub: AccountsText.closedReason(s.str("reason"), idleH: nil), at: s.num("at"))
                }
            }
        }
        .overlay { if data.isNull && error == nil { ProgressView() } }
        .navigationTitle("Was war los")
        .task(id: hours) { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private func list<V: View>(_ title: String, _ items: [JSON], content: @escaping (JSON) -> V) -> some View {
        if !items.isEmpty {
            Section("\(title) (\(items.count))") {
                ForEach(Array(items.enumerated()), id: \.offset) { _, s in content(s) }
            }
        }
    }

    private func row(_ s: JSON, sub: String, at: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(s.str("title", s.str("key"))).lineLimit(1)
                Spacer()
                if at > 0 { Text(TermText.ago(at)).font(.caption2).foregroundStyle(.secondary) }
            }
            Text(s.str("alias")).font(.caption).foregroundStyle(.secondary)
            if !sub.isEmpty { Text(sub).font(.footnote).foregroundStyle(.secondary).lineLimit(3) }
        }
    }

    private func load() async {
        do { data = try await model.rpc("digest", ["hours": .number(hours)], timeout: 40); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

/// "Token-Verbrauch": rpc `session_tokens`. `weighted` = input equivalents (cache read x0.1, write x1.25, output x5).
struct TokensView: View {
    @EnvironmentObject var model: AppModel
    @State private var days = 7
    @State private var data: JSON = .null
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Picker("Zeitraum", selection: $days) {
                    Text("1 Tag").tag(1); Text("7 Tage").tag(7); Text("30 Tage").tag(30)
                }.pickerStyle(.segmented)
            } footer: {
                Text("Gewichtet in Input-Äquivalenten (Cache lesen x0,1, Cache schreiben x1,25, Output x5). Zeigt, wo die Claude-Limits hingehen, auch ohne Pool-Helfer.")
            }
            if let e = error { Text(e).foregroundStyle(.red).font(.footnote) }
            if !data.isNull {
                let all = data["all"]
                Section("Gesamt") {
                    line("Gewichtet", AccountsText.tokens(all.num("weighted")))
                    line("Aufrufe", "\(all["calls"].int ?? 0)")
                    line("Input", AccountsText.tokens(all.num("input")))
                    line("Cache gelesen", AccountsText.tokens(all.num("cache_read")))
                    line("Output", AccountsText.tokens(all.num("output")))
                }
                if let accs = data["accounts"].object, !accs.isEmpty {
                    Section("Konten") {
                        ForEach(accs.keys.sorted(), id: \.self) { k in line(k, AccountsText.tokens(accs[k]?.num("weighted") ?? 0)) }
                    }
                }
                let sessions = data["sessions"].array.sorted { $0.num("weighted") > $1.num("weighted") }
                let top = sessions.first?.num("weighted") ?? 0
                Section("Sitzungen") {
                    ForEach(Array(sessions.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(s.str("title", s.str("key"))).lineLimit(1)
                                Spacer()
                                Text(AccountsText.tokens(s.num("weighted"))).font(.callout.monospacedDigit())
                            }
                            ProgressView(value: AccountsText.relative(s.num("weighted"), max: top))
                            Text("\(s.str("alias")) · \(s["calls"].int ?? 0) Aufrufe\(s.flag("alive") ? " · läuft" : "")").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay { if data.isNull && error == nil { ProgressView() } }
        .navigationTitle("Token-Verbrauch")
        .task(id: days) { await load() }
        .refreshable { await load() }
    }

    private func line(_ k: String, _ v: String) -> some View { HStack { Text(k); Spacer(); Text(v).monospacedDigit().foregroundStyle(.secondary) } }

    private func load() async {
        do { data = try await model.rpc("session_tokens", ["days": .number(Double(days)), "limit": 50], timeout: 60); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
