import SwiftUI
import RelayCore

private func clock(_ ts: Double) -> String {
    Date(timeIntervalSince1970: ts).formatted(date: .omitted, time: .shortened)
}

/// Windows of one account: bar, percent, reset, forecast.
struct UsageWindows: View {
    let a: UsageAccount
    var body: some View {
        ForEach(a.windows, id: \.name) { w in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(w.name).font(.callout)
                    Spacer()
                    Text("\(Int(w.pct.rounded())) %").font(.callout.monospacedDigit())
                        .foregroundStyle(w.pct >= 90 ? Color.red : (w.pct >= 70 ? Color.orange : Color.primary))
                }
                ProgressView(value: min(max(w.pct, 0), 100), total: 100).tint(w.pct >= 90 ? Color.red : (w.pct >= 70 ? Color.orange : Color.accentColor))
                if w.resetsAt > 0 { Text("Reset \(Date(timeIntervalSince1970: w.resetsAt), style: .relative)").font(.caption2).foregroundStyle(.secondary) }
                let f = AccountsText.forecast(w, clock: clock)
                if !f.isEmpty { Text(f).font(.caption2).foregroundStyle(w.runsOutAt != nil ? Color.orange : Color.secondary) }
            }
        }
    }
}

/// "Weitere Angaben" of the main Claude account: cloud credit, extra usage, use by product.
struct UsageExtrasRows: View {
    let x: UsageExtras

    private func extraLine(_ e: UsageExtras.Extra) -> String {
        var parts = ["\(AccountsText.money(e.used, e.currency)) verbraucht"]
        if let l = e.limit { parts.append("Limit \(AccountsText.money(l, e.currency))") }
        if let b = e.balance { parts.append("Guthaben \(AccountsText.money(b, e.currency))") }
        if e.autoReload { parts.append("lädt automatisch nach") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        if let c = x.credit {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cloud-Guthaben: \(AccountsText.money(c.left, c.currency)) übrig").font(.callout)
                Text("\(AccountsText.money(c.used, c.currency)) von \(AccountsText.money(c.limit, c.currency)) genutzt"
                     + (c.expiresAt > 0 ? " · läuft \(Date(timeIntervalSince1970: c.expiresAt).formatted(date: .abbreviated, time: .omitted)) ab" : "")
                     + (c.locked ? " · gesperrt" : "")).font(.caption).foregroundStyle(.secondary)
            }
        }
        if let e = x.extra {
            VStack(alignment: .leading, spacing: 2) {
                Text("Extra Usage: \(e.enabled ? "an" : "aus")").font(.callout)
                Text(extraLine(e)).font(.caption).foregroundStyle(.secondary)
                if !e.reason.isEmpty { Text(e.reason).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        if !x.byProduct.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nutzung je Produkt").font(.callout)
                ForEach(x.byProduct, id: \.name) { p in
                    HStack { Text(p.name); Spacer(); Text("\(Int(p.pct.rounded())) %").monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        ForEach(x.scoped, id: \.name) { p in
            HStack { Text(p.name); Spacer(); Text("\(Int(p.pct.rounded())) %").monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
        }
        if !x.error.isEmpty { Text("Weitere Angaben nicht lesbar: \(x.error)").font(.caption).foregroundStyle(.orange) }
    }
}

/// 5-hour and weekly limits of every account (rpc `usage`), extras, forecast and the cloud sessions.
struct UsageView: View {
    @EnvironmentObject var model: AppModel
    @State private var accounts: [UsageAccount] = []
    @State private var error: String?
    @State private var loading = false

    private var helperMissing: Bool { accounts.contains { AccountsText.isHelperMissing($0.error) } }

    var body: some View {
        List {
            if let e = error { Text(e).foregroundStyle(.red).font(.footnote) }
            if helperMissing {
                Section { Label(AccountsText.helperHint, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
            }
            ForEach(accounts) { a in
                Section("\(a.label) · \(a.alias)\(a.plan.isEmpty ? "" : " · \(a.plan)")") {
                    if a.gone { Text("Konto kann Claude Code nicht mehr nutzen").foregroundStyle(.red).font(.footnote) }
                    if AccountsText.isHelperMissing(a.error) {
                        Text("Keine Limits verfügbar (Pool-Helfer fehlt).").font(.caption).foregroundStyle(.secondary)
                    } else if !a.error.isEmpty {
                        Text(a.error).font(.caption).foregroundStyle(.secondary)
                    }
                    UsageWindows(a: a)
                    if let x = a.extras, !x.isEmpty { UsageExtrasRows(x: x) }
                    NavigationLink("Details") { AccountDetailView(a: a) }.font(.callout)
                }
            }
            CloudSection()
        }
        .overlay { if loading && accounts.isEmpty { ProgressView() } }
        .navigationTitle("Nutzung")
        .refreshable { await load(refresh: true); await model.loadCloud(refresh: true) }
        .task {
            await load(refresh: false)
            await model.loadCloud()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                await load(refresh: false)
                await model.loadCloud()
            }
        }
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

/// One account: all windows with forecast, plan, extras, what the gateway said.
struct AccountDetailView: View {
    let a: UsageAccount
    var body: some View {
        List {
            Section {
                row("Konto", "\(a.label) (\(a.alias))")
                row("Werkzeug", a.tool)
                if !a.plan.isEmpty { row("Plan", a.plan) }
                if a.gone { Text("Konto kann Claude Code nicht mehr nutzen (Abo beendet oder nicht bezahlt).").foregroundStyle(.red).font(.footnote) }
                if !a.error.isEmpty { Text(AccountsText.errorText(a.error)).font(.footnote).foregroundStyle(.secondary) }
            }
            if !a.windows.isEmpty { Section("Fenster") { UsageWindows(a: a) } }
            if let x = a.extras, !x.isEmpty {
                Section("Weitere Angaben") {
                    UsageExtrasRows(x: x)
                    if x.asOf > 0 { Text("Stand \(Date(timeIntervalSince1970: x.asOf), style: .relative)").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Section {
                Text("Die Aufteilung nach Projekt (usage_split) braucht auf dem PC den Pool-Helfer und das Team-Verzeichnis. Sie gibt es in dieser App nicht.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(a.label)
    }
    private func row(_ k: String, _ v: String) -> some View { HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary) } }
}

/// RAM per session tree (rpc `memory`), with close (with Undo) and reopen. Refreshes every 10 s while visible.
struct MemoryView: View {
    @EnvironmentObject var model: AppModel
    @State private var data: JSON = .null
    @State private var error: String?
    @State private var busyClose: JSON?
    @State private var showBusyClose = false

    var body: some View {
        List {
            if let e = error { Text(e).foregroundStyle(.red).font(.footnote) }
            if data.has("total_mb") {
                if data.num("available_mb") < 2048 {
                    Section {
                        Label("Weniger als 2 GB frei: unten eine Sitzung schließen", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }
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
                let live = data["sessions"].array.filter { !model.hidden.contains($0.str("key")) }
                let top = live.map { $0.num("mb") + $0.num("swap_mb") }.max() ?? 0
                Section("Sitzungen") {
                    ForEach(Array(live.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(s.str("title", s.str("key"))).lineLimit(1)
                                    Text("\(s.str("alias")) · \(s.str("state"))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(mb(s.num("mb") + s.num("swap_mb"))).font(.callout.monospacedDigit())
                            }
                            ProgressView(value: AccountsText.relative(s.num("mb") + s.num("swap_mb"), max: top))
                        }
                        .swipeActions {
                            if s.flag("closable") {
                                Button("Schließen", role: .destructive) { close(s) }
                            }
                        }
                    }
                }
                let closed = data["closed"].array
                if !closed.isEmpty {
                    Section("Geschlossen") {
                        ForEach(Array(closed.enumerated()), id: \.offset) { _, s in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.str("title", s.str("key"))).lineLimit(1)
                                    Text(closedLine(s)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Öffnen") { Task { do { _ = try await model.rpc("reopen", ["key": .string(s.str("key"))], timeout: 40) } catch { self.error = error.localizedDescription }; await load() } }
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
        .safeAreaInset(edge: .bottom) {
            if let s = model.undoable {
                HStack {
                    Text("Sitzung geschlossen.").font(.footnote)
                    Spacer()
                    Button("Rückgängig") { model.undoClose(s) }.font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal).padding(.bottom, 4)
            }
        }
        .confirmationDialog("Arbeitende Sitzung stoppen und schließen?", isPresented: $showBusyClose, titleVisibility: .visible, presenting: busyClose) { s in
            Button("Stoppen und schließen", role: .destructive) { softClose(s) }
        }
        .navigationTitle("RAM")
        .refreshable { await load() }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func gb(_ m: Double) -> String { String(format: "%.1f GB", m / 1024) }
    private func mb(_ m: Double) -> String { m >= 1024 ? gb(m) : "\(Int(m)) MB" }

    private func closedLine(_ s: JSON) -> String {
        var parts = [s.str("alias")]
        let at = s.num("closed_at")
        if at > 0 { let a = TermText.ago(at); parts.append(a == "jetzt" ? "gerade eben" : "vor \(a)") }
        parts.append(AccountsText.closedReason(s.str("reason"), idleH: s["idle_h"].double))
        if s.num("mb") > 0 { parts.append(AccountsText.memory(mb: s.num("mb"), swapMb: s.num("swap_mb"))) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func close(_ s: JSON) {
        if s.str("state") == "busy" { busyClose = s; showBusyClose = true } else { softClose(s) }
    }

    /// With a known session: row disappears, 6 s Undo. Otherwise the gateway closes at once.
    private func softClose(_ s: JSON) {
        let key = s.str("key")
        if let sess = model.sessions[key] ?? model.session(for: key), model.canClose(sess) { model.softClose(sess); return }
        Task {
            do { _ = try await model.rpc("close", ["key": .string(key), "mb": .number(s.num("mb")), "stop": .bool(s.str("state") == "busy")]) }
            catch { self.error = error.localizedDescription }
            await load()
        }
    }

    private func load() async {
        do { data = try await model.rpc("memory", [:], timeout: 30); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
