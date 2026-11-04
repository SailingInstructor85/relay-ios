import SwiftUI
import RelayCore

/// The overview: every session of every account, the ones waiting for the user first.
struct SessionsView: View {
    @EnvironmentObject var model: AppModel
    @State private var path = NavigationPath()
    @State private var search = ""
    @State private var showNew = false

    enum Dest: Hashable { case chat(String), settings, usage, memory, jarvis, jarvisListening }

    private var filtered: [Session] {
        let q = search.lowercased()
        return model.visibleSessions.filter {
            q.isEmpty || $0.name.lowercased().contains(q) || $0.cwd.lowercased().contains(q) || $0.alias.lowercased().contains(q)
        }
    }

    private func sorted(_ list: [Session]) -> [Session] {
        let pins = model.pinned
        return list.sorted { a, b in
            let pa = pins.contains(a.key), pb = pins.contains(b.key)
            if pa != pb { return pa }
            return a.lastActivity > b.lastActivity
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.state != .connected { connectionRow }
                let all = filtered
                let waiting = sorted(all.filter { $0.waits })
                let busy = sorted(all.filter { $0.state == "busy" && !$0.waits })
                let idle = sorted(all.filter { $0.state == "idle" && !$0.waits })
                let ended = sorted(all.filter { $0.exited || (!$0.waits && $0.state != "busy" && $0.state != "idle") })
                section("Wartet auf dich", waiting)
                section("Arbeitet", busy)
                section("Bereit", idle)
                section("Beendet", ended)
                if all.isEmpty && model.state == .connected {
                    ContentUnavailableView("Keine Sitzungen", systemImage: "terminal",
                                           description: Text("Starte eine neue Sitzung mit +"))
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
                        Toggle(isOn: $model.showDormant) { Label("Beendete zeigen", systemImage: "archivebox") }
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
            .onChange(of: model.openChat) { _, key in
                if let key { path = NavigationPath(); path.append(Dest.chat(key)); model.openChat = nil }
            }
            .onChange(of: model.openJarvis) { _, open in
                if open { path = NavigationPath(); path.append(Dest.jarvisListening); model.openJarvis = false }
            }
            .onAppear {
                if model.openJarvis { path.append(Dest.jarvisListening); model.openJarvis = false }
            }
            .safeAreaInset(edge: .top) { ErrorBanner(text: $model.lastError) }
        }
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

    @ViewBuilder private func section(_ title: String, _ list: [Session]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { s in
                    NavigationLink(value: Dest.chat(s.key)) { SessionRow(s: s, unread: model.unread.contains(s.key), pinned: model.pinned.contains(s.key), muted: model.muted.contains(s.key)) }
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
                            if s.alive && !s.exited {
                                Button(role: .destructive) { Task { await model.close(s) } } label: { Label("Schließen", systemImage: "xmark.circle") }
                            }
                        }
                }
            }
        }
    }
}

struct SessionRow: View {
    let s: Session
    let unread: Bool
    let pinned: Bool
    var muted = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: s.toolIcon).font(.system(size: 17, weight: .semibold)).frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                if unread { Circle().fill(.blue).frame(width: 10, height: 10).offset(x: 2, y: -2) }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.yellow) }
                    if muted { Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(.secondary) }
                    Text(s.name).font(.body.weight(unread ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(TermText.ago(s.lastActivity)).font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    StateBadge(state: s.shownState)
                    Text("\(s.alias) · \(s.folder)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let c = s.context, c.level != "ok" { Text("\(c.pct)%").font(.caption2).foregroundStyle(.orange) }
                }
                let detail = s.question?.text ?? (s.asksYou ? s.asksText : s.lastMessage)
                if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
        .padding(.vertical, 2)
    }
}
