import SwiftUI
import RelayCore

/// The overview: every session of every account, the ones waiting for the user first.
struct SessionsView: View {
    @EnvironmentObject var model: AppModel
    @State private var path = NavigationPath()
    @State private var search = ""
    @State private var showNew = false
    @State private var confirmClose: Session?
    @State private var showConfirmClose = false
    @State private var renameTarget: Session?
    @State private var showRename = false
    @State private var renameText = ""
    @State private var killTarget: Session?
    @State private var showKill = false

    enum Dest: Hashable { case chat(String), settings, usage, memory, jarvis, jarvisListening }

    private func haystack(_ s: Session) -> String { "\(s.name) \(s.alias) \(s.folder) \(s.cwd)" }

    private var filtered: [(s: Session, score: Int)] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return model.visibleSessions.compactMap { s -> (s: Session, score: Int)? in
            if q.isEmpty { return (s, 0) }
            return Fuzzy.score(q, haystack(s)).map { (s, $0) }
        }
    }

    private func sorted(_ list: [(s: Session, score: Int)]) -> [Session] {
        let pins = model.pinned
        let searching = !search.trimmingCharacters(in: .whitespaces).isEmpty
        return list.sorted { a, b in
            let pa = pins.contains(a.s.key), pb = pins.contains(b.s.key)
            if pa != pb { return pa }
            if searching && a.score != b.score { return a.score > b.score }
            return a.s.lastActivity > b.s.lastActivity
        }.map(\.s)
    }

    private var stale: Bool { model.state != .connected }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("Ansicht", selection: $model.showDormant) {
                        Text("Laufend").tag(false)
                        Text("Zuletzt").tag(true)
                    }.pickerStyle(.segmented)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                if model.state != .connected { connectionRow }
                let all = filtered
                if model.showDormant {
                    section("Zuletzt", sorted(all))
                } else {
                    let waiting = sorted(all.filter { $0.s.waits })
                    let busy = sorted(all.filter { $0.s.state == "busy" && !$0.s.waits })
                    let idle = sorted(all.filter { $0.s.state == "idle" && !$0.s.waits })
                    let other = sorted(all.filter { !$0.s.waits && $0.s.state != "busy" && $0.s.state != "idle" })
                    section("Wartet auf dich", waiting, extra: cloudWaiting)
                    section("Arbeitet", busy)
                    section("Bereit", idle)
                    section("Sonstige", other)
                }
                if all.isEmpty && model.state == .connected {
                    ContentUnavailableView(model.showDormant ? "Keine letzten Sitzungen" : "Keine Sitzungen", systemImage: "terminal",
                                           description: Text(model.showDormant ? "Beendete und geschlossene Sitzungen erscheinen hier." : "Starte eine neue Sitzung mit +"))
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Sitzungen suchen")
            .refreshable { await model.refresh() }
            .navigationTitle("Relay")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { path.append(Dest.jarvis) } label: { Label("Jarvis fragen", systemImage: "waveform") }
                        Button { path.append(Dest.usage) } label: { Label("Nutzung & Limits", systemImage: "gauge.with.dots.needle.33percent") }
                        Button { path.append(Dest.memory) } label: { Label("RAM-Monitor", systemImage: "memorychip") }
                        Button { model.markAllRead() } label: { Label("Alle gelesen", systemImage: "checkmark.circle") }
                            .disabled(model.unread.isEmpty)
                        Toggle(isOn: $model.showBackground) { Label("Hintergrundläufe", systemImage: "moon.zzz") }
                        Button { model.reconnect() } label: { Label("Neu verbinden", systemImage: "arrow.clockwise") }
                        Button { path.append(Dest.settings) } label: { Label("Einstellungen", systemImage: "gear") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(Dest.jarvisListening) } label: { Image(systemName: "mic") }
                        .accessibilityLabel("Jarvis per Sprache")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }.disabled(model.state != .connected)
                }
            }
            .navigationDestination(for: Dest.self) { d in
                switch d {
                case .chat(let key): ChatView(sessionKey: key)
                case .settings: SetupView()
                case .usage: UsageView()
                case .memory: MemoryView()
                case .jarvis: JarvisView()
                case .jarvisListening: JarvisView(autoListen: true)
                }
            }
            .sheet(isPresented: $showNew) {
                NewSessionView { target in
                    showNew = false
                    Task { // the placeholder appears shortly after launch
                        for _ in 0..<20 {
                            if let s = model.session(for: "tmux:\(target)") { path.append(Dest.chat(s.key)); return }
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            await model.refresh()
                        }
                    }
                }.environmentObject(model)
            }
            .onChange(of: model.showDormant) { _, _ in Task { await model.refresh() } }
            .onChange(of: model.showBackground) { _, _ in Task { await model.refresh() } }
            .onChange(of: model.openChat) { _, key in
                if let key { path = NavigationPath(); path.append(Dest.chat(key)); model.openChat = nil }
            }
            .onChange(of: model.openJarvis) { _, open in
                if open { path = NavigationPath(); path.append(Dest.jarvisListening); model.openJarvis = false }
            }
            .onAppear {
                if model.openJarvis { path.append(Dest.jarvisListening); model.openJarvis = false }
            }
            .task { await model.pollTriage() }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 4) {
                    TriageStrip(openNext: openNext, openUsage: { path.append(Dest.usage) }, openMemory: { path.append(Dest.memory) })
                    ErrorBanner(text: $model.lastError)
                }
            }
            .safeAreaInset(edge: .bottom) { undoBar }
            .confirmationDialog("Arbeitende Sitzung stoppen und schließen?", isPresented: $showConfirmClose, titleVisibility: .visible, presenting: confirmClose) { s in
                Button("Stoppen und schließen", role: .destructive) { model.softClose(s) }
            }
            .confirmationDialog("Sitzung töten?", isPresented: $showKill, titleVisibility: .visible, presenting: killTarget) { s in
                Button("Töten", role: .destructive) { Task { await model.kill(s) } }
            } message: { _ in Text("Der Terminal der Sitzung wird beendet.") }
            .alert("Sitzung umbenennen", isPresented: $showRename) {
                TextField("Name", text: $renameText)
                Button("Abbrechen", role: .cancel) {}
                Button("Umbenennen") { if let s = renameTarget { Task { await model.rename(s, to: renameText) } } }
            }
        }
    }

    private func openNext() {
        if let n = Triage.next(model.triageSessions, unread: model.unread) { path.append(Dest.chat(n.key)) }
    }

    @ViewBuilder private var undoBar: some View {
        if let s = model.undoable {
            HStack {
                Text("Sitzung geschlossen.").font(.footnote)
                Spacer()
                Button("Rückgängig") { model.undoClose(s) }.font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal).padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var cloudWaiting: [CloudSession] {
        guard !model.showDormant else { return [] }
        let q = search.trimmingCharacters(in: .whitespaces)
        return model.cloudSessions.filter { $0.waiting && (q.isEmpty || Fuzzy.score(q, "\($0.title) \($0.repo)") != nil) }
    }

    @ViewBuilder private var connectionRow: some View {
        HStack {
            if model.state == .connecting { ProgressView().padding(.trailing, 4) }
            else { Image(systemName: "bolt.horizontal.circle").foregroundStyle(.orange) }
            Text(model.state.label).font(.footnote)
            Spacer()
            Button("Erneut") { model.reconnect() }.font(.footnote)
        }
    }

    @ViewBuilder private func section(_ title: String, _ list: [Session], extra: [CloudSession] = []) -> some View {
        if !list.isEmpty || !extra.isEmpty {
            Section(title) {
                ForEach(list) { s in row(s) }
                ForEach(extra) { c in CloudRow(c: c) }
            }
        }
    }

    @ViewBuilder private func row(_ s: Session) -> some View {
        NavigationLink(value: Dest.chat(s.key)) {
            SessionRow(s: s, unread: model.unread.contains(s.key), pinned: model.pinned.contains(s.key), muted: model.muted.contains(s.key),
                       stale: stale, look: model.look, query: search)
        }
        .contextMenu {
            if s.tool == "claude" && s.liveTmux != nil {
                Button { renameTarget = s; renameText = ""; showRename = true } label: { Label("Umbenennen...", systemImage: "pencil") }
            }
            Button { model.togglePin(s.key) } label: { Label(model.pinned.contains(s.key) ? "Loslösen" : "Anheften", systemImage: "pin") }
            if s.waits || model.unread.contains(s.key) {
                Button { Task { await model.done(s) } } label: { Label("Erledigt", systemImage: "checkmark") }
            }
            if !s.exited && (s.attachable || s.tmuxSession != nil) {
                Button(role: .destructive) { killTarget = s; showKill = true } label: { Label("Töten", systemImage: "bolt.slash") }
            }
        }
        .swipeActions(edge: .leading) {
            if s.waits || model.unread.contains(s.key) {
                Button { Task { await model.done(s) } } label: { Label("Erledigt", systemImage: "checkmark") }.tint(.green)
            }
            Button { model.togglePin(s.key) } label: { Label("Pin", systemImage: "pin") }.tint(.yellow)
            Button { model.toggleMute(s.key) } label: {
                Label(model.muted.contains(s.key) ? "Ton an" : "Stumm", systemImage: model.muted.contains(s.key) ? "bell" : "bell.slash")
            }.tint(.gray)
        }
        .swipeActions(edge: .trailing) {
            if model.canClose(s) {
                Button(role: .destructive) {
                    if s.state == "busy" { confirmClose = s; showConfirmClose = true } else { model.softClose(s) }
                } label: { Label("Schließen", systemImage: "xmark.circle") }
            }
        }
    }
}

/// The slim line under the navigation bar: who needs you, RAM and CPU of the Desktop, the accounts' limits.
struct TriageStrip: View {
    @EnvironmentObject var model: AppModel
    let openNext: () -> Void
    let openUsage: () -> Void
    let openMemory: () -> Void

    private func color(_ level: Int) -> Color { level >= 2 ? .red : (level == 1 ? .orange : .secondary) }

    var body: some View {
        let count = Triage.shortCount(Triage.counts(model.triageSessions, unread: model.unread))
        let offline = model.state != .connected
        let ram = offline ? nil : Triage.ram(model.memory)
        let cpu = offline ? nil : Triage.cpu(model.memory)
        let quotas = offline ? [] : Triage.quota(model.usage)
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let staleText = offline ? Triage.staleText(lastSync: model.lastSync, now: ctx.date) : ""
            if !count.isEmpty || ram != nil || cpu != nil || !quotas.isEmpty || !staleText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        if !count.isEmpty {
                            Button(action: openNext) { Text(count).fontWeight(.semibold) }
                                .foregroundStyle(count.contains("brauch") ? Color.red : Color.accentColor)
                        }
                        if !staleText.isEmpty { Text(staleText).foregroundStyle(.secondary) }
                        if let r = ram {
                            Button(action: openMemory) { Text("RAM \(r.text)").foregroundStyle(color(r.level)) }
                        }
                        if let c = cpu {
                            Button(action: openMemory) { Text(c.text).foregroundStyle(color(c.level)) }
                        }
                        ForEach(quotas) { q in
                            Button(action: openUsage) {
                                HStack(spacing: 4) {
                                    Text("\(q.alias) \(q.text)").foregroundStyle(color(q.level))
                                    if !q.week.isEmpty { Text(q.week).foregroundStyle(color(q.weekLevel)) }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
                .padding(.vertical, 6)
                .background(.bar)
            }
        }
    }
}

struct CloudRow: View {
    let c: CloudSession
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cloud").frame(width: 38, height: 38).background(Color.accentColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    StateDot(state: "needs_input")
                    Text(c.title).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(TermText.ago(c.lastAt)).font(.caption2).foregroundStyle(.secondary)
                }
                Text("Cloud" + (c.repo.isEmpty ? "" : " · \(c.repo)")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                let q = c.question.isEmpty ? c.detail : c.question
                if !q.isEmpty { Text(q).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { if let u = URL(string: c.url), !c.url.isEmpty { UIApplication.shared.open(u) } }
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

/// The project's initials (or configured emoji) on the project's colour; grey when ended or offline.
struct SessionAvatar: View {
    let s: Session
    let unread: Bool
    let stale: Bool
    let look: Avatars.Look
    var body: some View {
        let glyph = Avatars.glyph(cwd: s.cwd, title: s.name, look: look)
        let grey = s.exited || stale
        let bg: Color = grey ? .gray : Color(rgb: Avatars.color(cwd: s.cwd, look: look))
        let emoji = glyph?.unicodeScalars.contains { $0.value > 0x2000 } ?? false
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle().fill(bg.opacity(grey ? 0.55 : 1))
                if emoji { Text(glyph ?? "").font(.system(size: 20)).opacity(grey ? 0.6 : 1) }
                else { Text(glyph ?? Avatars.initials(s.cwd)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white) }
            }
            .frame(width: 38, height: 38)
            if unread { Circle().fill(.blue).frame(width: 11, height: 11).overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5)).offset(x: 2, y: -2) }
        }
        .accessibilityHidden(true)
    }
}

private struct Tag: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color).lineLimit(1)
    }
}

struct SessionRow: View {
    let s: Session
    let unread: Bool
    let pinned: Bool
    var muted = false
    var stale = false
    var look = Avatars.Look()
    var query = ""

    /// The title with the letters the search matched in bold.
    private var title: Text {
        let name = s.name
        var pos = Set<Int>()
        for t in Fuzzy.terms(query) { pos.formUnion(Fuzzy.positions(t, name)) }
        guard !pos.isEmpty else { return Text(name) }
        var out = Text("")
        var run = ""
        var bold = false
        for (i, ch) in name.enumerated() {
            let b = pos.contains(i)
            if b != bold && !run.isEmpty { out = out + (bold ? Text(run).bold() : Text(run)); run = "" }
            bold = b
            run.append(ch)
        }
        if !run.isEmpty { out = out + (bold ? Text(run).bold() : Text(run)) }
        return out
    }

    private var closedText: String {
        switch s.closedReason {
        case "user": return "geschlossen"
        case "idle": return "geschlossen (inaktiv)"
        case "pressure": return "geschlossen (RAM)"
        case "rotate": return "geschlossen (rotiert)"
        case "cancelled": return "geschlossen (abgebrochen)"
        default: return "geschlossen"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SessionAvatar(s: s, unread: unread, stale: stale, look: look)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.yellow) }
                    if muted { Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(.secondary) }
                    title.font(.body.weight(unread ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(TermText.ago(s.lastActivity)).font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    StateDot(state: s.shownState, stale: stale)
                    Tag(text: s.alias)
                    Text(s.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let c = s.context, c.level != "ok" { Tag(text: "\(c.pct)%", color: c.level == "full" ? .red : .orange) }
                    if s.hibernated { Tag(text: "ruht") }
                    if s.closed { Tag(text: closedText) }
                }
                let detail = s.question?.text ?? (s.asksYou ? s.asksText : s.lastMessage)
                if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
