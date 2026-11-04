import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import RelayCore

/// One session as a chat: its transcript, the live menu card (questions, pickers, permission prompts) and an input bar
/// whose text goes into the real TUI through tmux.
struct ChatView: View {
    @EnvironmentObject var model: AppModel
    let sessionKey: String

    @State private var messages: [TMessage] = []
    @State private var before: String?
    @State private var loading = false
    @State private var loadedOnce = false
    @State private var input = ""
    @State private var sending = false
    @State private var menu: ScreenMenu?
    @State private var status = ""
    @State private var error: String?
    @State private var confirmForce: String?
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var uploadInfo = ""
    @State private var showScreen = false
    @State private var showSearch = false
    @State private var highlight: String?
    @State private var jumpTo: String?
    @FocusState private var focused: Bool

    private var session: Session? { model.session(for: sessionKey) }
    private var key: String { session?.key ?? sessionKey }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if before != nil {
                            Button(loading ? "Lade…" : "Ältere Nachrichten laden") { Task { await loadOlder() } }
                                .font(.footnote).frame(maxWidth: .infinity).padding(.top, 8)
                        }
                        ForEach(messages) { m in MessageRow(m: m, highlighted: m.id == highlight).id(m.id) }
                        if let s = session, s.state == "busy" {
                            HStack(spacing: 8) { ProgressView(); Text(status.isEmpty ? "arbeitet…" : status).font(.footnote).foregroundStyle(.secondary) }
                                .padding(.horizontal)
                        }
                        if let s = session, s.asksYou, !s.asksText.isEmpty {
                            AsksCard(text: s.asksText) { Task { await model.done(s) } }
                        }
                        if let m = menu, let s = session {
                            MenuCard(menu: m, session: s) { await refreshScreen() }
                        } else if let s = session, let q = s.question {
                            QuestionCard(q: q)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: menu?.id) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: jumpTo) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .top) }; jumpTo = nil }
                }
            }
            if let e = error { ErrorBanner(text: Binding(get: { e }, set: { error = $0 })).padding(.vertical, 4) }
            if !uploadInfo.isEmpty { Text(uploadInfo).font(.caption).foregroundStyle(.secondary).padding(.top, 4) }
            inputBar
        }
        .navigationTitle(session?.name ?? "Sitzung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .sheet(isPresented: $showSearch) {
            ChatSearchView(sessionKey: key) { id, index in Task { await jump(to: id, index: index) } }.environmentObject(model)
        }
        .sheet(isPresented: $showScreen) {
            if let s = session { NavigationStack { ScreenView(session: s) }.environmentObject(model) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { Task { await uploadFile(url) } }
        }
        .onChange(of: photo) { _, item in if let item { Task { await uploadPhoto(item) } } }
        .confirmationDialog("Die Sitzung arbeitet gerade.", isPresented: Binding(get: { confirmForce != nil }, set: { if !$0 { confirmForce = nil } }), titleVisibility: .visible) {
            Button("Trotzdem senden") { if let t = confirmForce { Task { await send(t, force: true) } } }
            Button("Abbrechen", role: .cancel) {}
        }
        .task(id: key) { await openChat() }
        .onDisappear {
            model.visibleChat = nil
            model.transcriptListeners[sessionKey] = nil
            Task { _ = try? await model.rpc("unwatch", ["key": .string(key)]) }
        }
    }

    // MARK: input

    private var inputBar: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["/compact", "/model", "/usage", "/clear", "/resume", "/status", "/effort"], id: \.self) { c in
                        Button(c) { input = c + " "; focused = true }.font(.caption).buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }
                    Button { Task { if let s = session { try? await model.sendKeys(s, ["Escape"]); await refreshScreen() } } } label: { Text("Esc") }
                        .font(.caption).buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.red)
                }.padding(.horizontal)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    PhotosPicker(selection: $photo, matching: .images) { Label("Foto", systemImage: "photo") }
                    Button { importing = true } label: { Label("Datei", systemImage: "doc") }
                } label: { Image(systemName: "paperclip").font(.title3) }
                TextField("Nachricht an die Sitzung", text: $input, axis: .vertical)
                    .lineLimit(1...6).focused($focused)
                    .padding(8).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                Button { Task { await send(input) } } label: {
                    Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill").font(.system(size: 30))
                }.disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending || session == nil)
            }
            .padding(.horizontal).padding(.bottom, 6)
        }
        .padding(.top, 6)
        .background(.bar)
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let s = session {
                    if s.liveTmux != nil { Button { showScreen = true } label: { Label("Live-Bildschirm", systemImage: "terminal") } }
                    Button { showSearch = true } label: { Label("Im Verlauf suchen", systemImage: "magnifyingglass") }
                    Button { model.togglePin(s.key) } label: { Label(model.pinned.contains(s.key) ? "Loslösen" : "Anheften", systemImage: "pin") }
                    Button { model.toggleMute(s.key) } label: {
                        Label(model.muted.contains(s.key) ? "Mitteilungen an" : "Stummschalten", systemImage: model.muted.contains(s.key) ? "bell" : "bell.slash")
                    }
                    if s.waits { Button { Task { await model.done(s) } } label: { Label("Als erledigt markieren", systemImage: "checkmark") } }
                    if s.exited || s.closed || s.hibernated {
                        Button { Task { do { _ = try await model.reopen(s); await model.refresh() } catch { self.error = error.localizedDescription } } } label: { Label("Wieder öffnen", systemImage: "arrow.uturn.backward") }
                    } else if s.alive {
                        Button(role: .destructive) { Task { await model.close(s) } } label: { Label("Sitzung schließen", systemImage: "xmark.circle") }
                    }
                    if !s.remoteUrl.isEmpty, let u = URL(string: s.remoteUrl) { Link(destination: u) { Label("In Claude öffnen", systemImage: "safari") } }
                    Section("\(s.alias) · \(s.tool)") {
                        Text(s.cwd)
                        if let c = s.context { Text("Kontext: \(c.label) (\(c.pct) %)") }
                    }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if session?.liveTmux != nil { Button { showScreen = true } label: { Image(systemName: "terminal") } }
        }
    }

    // MARK: loading

    private func openChat() async {
        model.visibleChat = key
        model.markRead(key)
        model.transcriptListeners[sessionKey] = { k, msgs in
            guard k == key || session?.matches(k) == true else { return }
            let known = Set(messages.map(\.id))
            messages.append(contentsOf: msgs.filter { !known.contains($0.id) })
        }
        // wait for the link if it is just coming up
        for _ in 0..<40 where model.state != .connected { try? await Task.sleep(nanoseconds: 250_000_000) }
        if !loadedOnce { await loadLatest() }
        _ = try? await model.rpc("watch", ["key": .string(key)])
        // poll the menu and the running status while the chat is open
        var tick = 0
        while !Task.isCancelled {
            if let s = session {
                if s.liveTmux != nil && (s.state != "busy" || tick % 2 == 0) { await refreshScreen() }
                if s.state == "busy" { await refreshRunning() } else { status = "" }
            }
            tick += 1
            try? await Task.sleep(nanoseconds: (session?.state == "busy" ? 1_500_000_000 : 2_500_000_000))
        }
    }

    private func loadLatest() async {
        loading = true; defer { loading = false }
        do {
            let r = try await model.rpc("transcript", ["key": .string(key), "limit": 50])
            messages = r["messages"].array.map(TMessage.from)
            before = r["before"].string
            loadedOnce = true
        } catch { self.error = error.localizedDescription }
    }

    private func loadOlder() async {
        guard let b = before, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let r = try await model.rpc("transcript", ["key": .string(key), "limit": 50, "before": .string(b)])
            let older = r["messages"].array.map(TMessage.from)
            let known = Set(messages.map(\.id))
            messages.insert(contentsOf: older.filter { !known.contains($0.id) }, at: 0)
            before = r["before"].string
        } catch { self.error = error.localizedDescription }
    }

    /// Shows a search hit: loads the transcript from its index when it isn't loaded yet, scrolls there, highlights it.
    private func jump(to id: String, index: Int) async {
        if !messages.contains(where: { $0.id == id }) {
            loading = true; defer { loading = false }
            do {
                let r = try await model.rpc("transcript", ["key": .string(key), "from": .number(Double(index))], timeout: 30)
                messages = r["messages"].array.map(TMessage.from)
                before = r["before"].string
            } catch { self.error = error.localizedDescription; return }
        }
        try? await Task.sleep(nanoseconds: 350_000_000) // let the list lay out first
        highlight = id
        jumpTo = id
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if highlight == id { withAnimation { highlight = nil } }
    }

    private func refreshScreen() async {
        guard let s = session, s.liveTmux != nil else { menu = nil; return }
        if let r = try? await model.rpc("screen", ["target": .string(s.target), "lines": 60, "escapes": false, "menu": true], timeout: 10) {
            let m = ScreenMenu.from(r["menu"])
            if m?.id != menu?.id || (m == nil) != (menu == nil) { menu = m }
        }
    }

    private func refreshRunning() async {
        guard let r = try? await model.rpc("running", ["key": .string(key)], timeout: 8) else { return }
        let st = r["status"]
        var parts: [String] = []
        if let v = st["verb"].string { parts.append(v) }
        if let e = st["elapsed"].string { parts.append(e) }
        if let t = st["tokens"].string { parts.append(t) }
        let items = r["running"].array.map { $0.str("label", $0.str("kind")) }.filter { !$0.isEmpty }
        if let last = items.last { parts.append(last) }
        status = parts.joined(separator: " · ")
    }

    private func send(_ text: String, force: Bool = false) async {
        guard let s = session else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        sending = true; defer { sending = false }
        do {
            try await model.send(s, text: t, force: force)
            input = ""
            error = nil
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refreshScreen()
        } catch let e as RelayError where e.remote && (e.message.lowercased().contains("busy") || e.message.lowercased().contains("arbeitet")) {
            confirmForce = t
        } catch { self.error = error.localizedDescription }
    }

    // MARK: attachments

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { error = "Foto konnte nicht geladen werden"; return }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        await upload(name: "foto-\(Int(Date().timeIntervalSince1970)).\(ext)", data: data)
    }

    private func uploadFile(_ url: URL) async {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { error = "Datei konnte nicht gelesen werden"; return }
        await upload(name: url.lastPathComponent, data: data)
    }

    private func upload(name: String, data: Data) async {
        guard data.count <= 50 * 1024 * 1024 else { error = "Datei ist größer als 50 MB"; return }
        uploadInfo = "Lade \(name) hoch…"
        do {
            let path = try await model.upload(name: name, data: data) { p in Task { @MainActor in uploadInfo = "Lade \(name) hoch… \(Int(p * 100)) %" } }
            input = (input.isEmpty ? "" : input + " ") + path + " "
            uploadInfo = ""
            focused = true
        } catch { uploadInfo = ""; self.error = error.localizedDescription }
    }
}

// MARK: message rendering

struct MessageRow: View {
    let m: TMessage
    var highlighted = false
    @State private var toolsOpen = false

    var body: some View {
        content
            .background(highlighted ? Color.yellow.opacity(0.25) : Color.clear)
            .animation(.easeInOut, value: highlighted)
    }

    @ViewBuilder private var content: some View {
        switch m.role {
        case "user":
            HStack { Spacer(minLength: 40); Text(m.text).textSelection(.enabled).padding(10)
                .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 14)) }
            .padding(.horizontal)
        case "system":
            Text(m.text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.horizontal)
        case "tool":
            toolRow
        default:
            VStack(alignment: .leading, spacing: 6) {
                if !m.text.isEmpty { MarkdownText(text: m.text) }
                if !m.tools.isEmpty { toolRow }
                if !m.files.isEmpty {
                    ForEach(m.files, id: \.path) { f in
                        Label(f.name, systemImage: f.kind == "image" ? "photo" : "doc").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder private var toolRow: some View {
        if !m.tools.isEmpty {
            DisclosureGroup(isExpanded: $toolsOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(m.tools.enumerated()), id: \.offset) { _, t in
                        Text("\(t.name): \(t.summary)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label(m.tools.count == 1 ? "\(m.tools[0].name) · \(m.tools[0].summary)" : "\(m.tools.count) Werkzeugaufrufe",
                      systemImage: "wrench.and.screwdriver").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal)
        } else if !m.text.isEmpty {
            Text(m.text).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(6).padding(.horizontal)
        }
    }
}

/// Markdown with fenced code blocks shown as monospaced boxes; the rest as inline markdown.
struct MarkdownText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.split(text).enumerated()), id: \.offset) { _, part in
                if part.code {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(part.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(8)
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(Self.inline(part.text)).textSelection(.enabled)
                }
            }
        }
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    static func split(_ s: String) -> [(code: Bool, text: String)] {
        var out: [(code: Bool, text: String)] = []
        var code = false
        var buf: [Substring] = []
        for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let t = buf.joined(separator: "\n")
                if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append((code, t)) }
                buf = []; code.toggle(); continue
            }
            buf.append(line)
        }
        let t = buf.joined(separator: "\n")
        if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append((code, t)) }
        return out
    }
}

struct AsksCard: View {
    let text: String
    let done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Die Sitzung fragt dich", systemImage: "questionmark.bubble").font(.subheadline.weight(.semibold))
            Text(text).font(.callout)
            Button("Erledigt", action: done).buttonStyle(.bordered)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
    }
}

struct QuestionCard: View {
    let q: Question
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(q.header.isEmpty ? "Frage" : q.header, systemImage: "questionmark.circle").font(.subheadline.weight(.semibold))
            Text(q.text)
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                Text("\(i + 1). \(o.label)").font(.callout)
            }
            Text("Antwortkarte erscheint, sobald der Bildschirm geladen ist.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
    }
}

/// Search over the whole transcript of one session (rpc `transcript_search`); a hit jumps there in the chat.
struct ChatSearchView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sessionKey: String
    let onPick: (String, Int) -> Void

    @State private var query = ""
    @State private var hits: [JSON] = []
    @State private var searched = ""
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                    Button {
                        onPick(h.str("id"), h["index"].int ?? 0)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(h.str("role") == "user" ? "Du" : "Agent").font(.caption.weight(.semibold))
                                Spacer()
                                Text(TermText.ago(h.num("ts"))).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(h.str("snippet")).font(.callout).lineLimit(4)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !searching && hits.isEmpty && searched.count >= 2 && error == nil {
                    Text("Nichts gefunden für „\(searched)“").foregroundStyle(.secondary)
                }
                if searching { HStack { Spacer(); ProgressView(); Spacer() } }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Im Verlauf suchen")
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 450_000_000)
                if !Task.isCancelled { await run() }
            }
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { hits = []; searched = ""; return }
        searching = true; defer { searching = false }
        do {
            let r = try await model.rpc("transcript_search", ["key": .string(sessionKey), "query": .string(q), "limit": 100], timeout: 20)
            hits = r["matches"].array
            searched = q
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
