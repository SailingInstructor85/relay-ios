import SwiftUI
import RelayCore

/// 5-hour and weekly limits of every account (rpc `usage`).
struct UsageView: View {
    @EnvironmentObject var model: AppModel
    @State private var accounts: [UsageAccount] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            if let e = error { Text(e).foregroundStyle(.red).font(.footnote) }
            ForEach(accounts) { a in
                Section("\(a.label) · \(a.alias)\(a.plan.isEmpty ? "" : " · \(a.plan)")") {
                    if a.gone { Text("Konto kann Claude Code nicht mehr nutzen").foregroundStyle(.red).font(.footnote) }
                    if !a.error.isEmpty { Text(a.error).font(.caption).foregroundStyle(.secondary) }
                    ForEach(a.windows, id: \.name) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(w.name).font(.callout)
                                Spacer()
                                Text("\(Int(w.pct.rounded())) %").font(.callout.monospacedDigit()).foregroundStyle(w.pct >= 90 ? Color.red : (w.pct >= 70 ? Color.orange : Color.primary))
                            }
                            ProgressView(value: min(max(w.pct, 0), 100), total: 100).tint(w.pct >= 90 ? Color.red : (w.pct >= 70 ? Color.orange : Color.accentColor))
                            HStack {
                                if w.resetsAt > 0 { Text("Reset \(Date(timeIntervalSince1970: w.resetsAt), style: .relative)").font(.caption2).foregroundStyle(.secondary) }
                                if let r = w.runsOutAt { Text("· leer um \(Date(timeIntervalSince1970: r), style: .time)").font(.caption2).foregroundStyle(.orange) }
                            }
                        }
                    }
                }
            }
        }
        .overlay { if loading && accounts.isEmpty { ProgressView() } }
        .navigationTitle("Nutzung")
        .refreshable { await load(refresh: true) }
        .task { await load(refresh: false) }
    }

    private func load(refresh: Bool) async {
        loading = true; defer { loading = false }
        do {
            let r = try await model.rpc("usage", ["refresh": .bool(refresh)], timeout: 60)
            accounts = r["accounts"].array.map(UsageAccount.from)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// RAM per session tree (rpc `memory`), with close and reopen.
struct MemoryView: View {
    @EnvironmentObject var model: AppModel
    @State private var data: JSON = .null
    @State private var error: String?

    var body: some View {
        List {
            if let e = error { Text(e).foregroundStyle(.red).font(.footnote) }
            if data.has("total_mb") {
                Section("Desktop") {
                    let total = data.num("total_mb")
                    let avail = data.num("available_mb")
                    VStack(alignment: .leading) {
                        Text("RAM: \(gb(total - avail)) von \(gb(total)) belegt")
                        ProgressView(value: max(0, total - avail), total: max(total, 1))
                    }
                    if data.num("swap_total_mb") > 0 { Text("Swap: \(gb(data.num("swap_used_mb"))) von \(gb(data.num("swap_total_mb")))").font(.callout) }
                    if data.has("cpu_pct") { Text("CPU: \(Int(data.num("cpu_pct"))) % · Last \(String(format: "%.2f", data.num("load1")))").font(.callout) }
                }
                Section("Sitzungen") {
                    ForEach(Array(data["sessions"].array.enumerated()), id: \.offset) { _, s in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(s.str("title", s.str("key"))).lineLimit(1)
                                Text("\(s.str("alias")) · \(s.str("state"))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(mb(s.num("mb") + s.num("swap_mb"))).font(.callout.monospacedDigit())
                        }
                        .swipeActions {
                            if s.flag("closable") {
                                Button("Schließen", role: .destructive) {
                                    Task { _ = try? await model.rpc("close", ["key": .string(s.str("key")), "mb": .number(s.num("mb")), "stop": true]); await load() }
                                }
                            }
                        }
                    }
                }
                let closed = data["closed"].array
                if !closed.isEmpty {
                    Section("Geschlossen") {
                        ForEach(Array(closed.enumerated()), id: \.offset) { _, s in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(s.str("title", s.str("key"))).lineLimit(1)
                                    Text("\(s.str("alias")) · \(s.str("reason"))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Öffnen") { Task { _ = try? await model.rpc("reopen", ["key": .string(s.str("key"))], timeout: 40); await load() } }
                                    .buttonStyle(.bordered).font(.caption)
                            }
                        }
                    }
                }
                Section("Sonstiges") {
                    ForEach(Array(data["others"].array.prefix(8).enumerated()), id: \.offset) { _, o in
                        HStack { Text(o.str("name")).lineLimit(1); Spacer(); Text(mb(o.num("mb"))).font(.callout.monospacedDigit()) }
                    }
                }
            }
        }
        .overlay { if data.isNull && error == nil { ProgressView() } }
        .navigationTitle("RAM")
        .refreshable { await load() }
        .task { await load() }
    }

    private func gb(_ m: Double) -> String { String(format: "%.1f GB", m / 1024) }
    private func mb(_ m: Double) -> String { m >= 1024 ? gb(m) : "\(Int(m)) MB" }

    private func load() async {
        do { data = try await model.rpc("memory", [:], timeout: 30); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

