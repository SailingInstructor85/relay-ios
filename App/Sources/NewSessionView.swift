import SwiftUI
import RelayCore

/// Starts a new agent session: account, folder (recent, search or browse), optional first prompt.
struct NewSessionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let onLaunched: (String) -> Void

    @State private var alias = ""
    @State private var cwd = ""
    @State private var prompt = ""
    @State private var name = ""
    @State private var recent: [String] = []
    @State private var query = ""
    @State private var found: [DirEntry] = []
    @State private var browsing: String?
    @State private var listing: [DirEntry] = []
    @State private var parent: String?
    @State private var error: String?
    @State private var launching = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Konto") {
                    Picker("Konto", selection: $alias) {
                        Text("auto (freies Kontingent)").tag("auto")
                        ForEach(model.accounts) { a in Text("\(a.label) (\(a.alias))\(a.loggedIn ? "" : " – nicht angemeldet")").tag(a.alias) }
                    }
                }
                Section("Ordner") {
                    HStack {
                        Image(systemName: "folder")
                        Text(cwd.isEmpty ? "Kein Ordner gewählt" : cwd).font(.callout).foregroundStyle(cwd.isEmpty ? .secondary : .primary).lineLimit(2)
                    }
                    TextField("Ordner suchen…", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { Task { await find() } }
                    ForEach(found) { d in dirButton(d.path, git: d.isGit) }
                    if query.isEmpty {
                        ForEach(Array(FavDirs.ordered(favs: model.favDirs, recent: recent).prefix(10 + model.favDirs.count)), id: \.self) { p in dirButton(p, git: false) }
                    }
                    Button { Task { await browse(browsing ?? "~") } } label: { Label("Durchsuchen", systemImage: "folder.badge.gearshape") }
                }
                if let b = browsing {
                    Section(b) {
                        if let p = parent { Button { Task { await browse(p) } } label: { Label("..", systemImage: "arrow.up") } }
                        Button { cwd = b } label: { Label("Diesen Ordner wählen", systemImage: "checkmark.circle") }
                        Button {
                            Task {
                                guard !name.isEmpty else { error = "Unten zuerst einen Namen eingeben"; return }
                                do { let r = try await model.rpc("mkdir", ["path": .string(b + "/" + name)]); cwd = r.str("path"); await browse(b) }
                                catch { self.error = error.localizedDescription }
                            }
                        } label: { Label("Neuer Ordner mit dem Namen unten", systemImage: "folder.badge.plus") }
                        ForEach(listing) { d in
                            Button { Task { await browse(d.path) } } label: {
                                Label(d.name, systemImage: d.isGit ? "arrow.triangle.branch" : "folder")
                            }
                        }
                    }
                }
                Section("Optional") {
                    TextField("Erste Nachricht", text: $prompt, axis: .vertical).lineLimit(2...6)
                    TextField("Name (auch für neuen Ordner)", text: $name)
                }
                if let e = error { Section { Text(e).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("Neue Sitzung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(launching ? "Starte…" : "Starten") { Task { await launch() } }.disabled(cwd.isEmpty || alias.isEmpty || launching)
                }
            }
            .task {
                if alias.isEmpty, !model.lastAlias.isEmpty, model.lastAlias == "auto" || model.accounts.contains(where: { $0.alias == model.lastAlias }) { alias = model.lastAlias }
                if alias.isEmpty { alias = model.accounts.first { $0.tool == "claude" && $0.loggedIn }?.alias ?? model.accounts.first?.alias ?? "auto" }
                if let r = try? await model.rpc("recent_dirs", ["limit": 30]) {
                    recent = r["dirs"].array.map { $0.str("path") }.filter { !$0.isEmpty }
                }
            }
            .onChange(of: query) { _, q in
                Task { try? await Task.sleep(nanoseconds: 400_000_000); if q == query { await find() } }
            }
        }
    }

    private func dirButton(_ path: String, git: Bool) -> some View {
        HStack {
            Button { cwd = path } label: {
                HStack {
                    Image(systemName: git ? "arrow.triangle.branch" : "clock")
                    Text(path.replacingOccurrences(of: "/home/\(model.user)", with: "~")).lineLimit(1).truncationMode(.head)
                    Spacer()
                    if cwd == path { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }.foregroundStyle(.primary).buttonStyle(.borderless)
            Button { model.favDirs = FavDirs.toggled(model.favDirs, path) } label: {
                Image(systemName: model.favDirs.contains(path) ? "star.fill" : "star").foregroundStyle(.yellow)
            }.buttonStyle(.borderless).accessibilityLabel(model.favDirs.contains(path) ? "Favorit entfernen" : "Als Favorit merken")
        }
    }

    private func find() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { found = []; return }
        if let r = try? await model.rpc("find_dirs", ["query": .string(q), "limit": 20]) {
            found = r["dirs"].array.map { DirEntry(name: $0.str("display"), path: $0.str("path"), isGit: $0.flag("is_git")) }
        }
    }

    private func browse(_ path: String) async {
        do {
            let r = try await model.rpc("list_dirs", ["path": .string(path)])
            browsing = r.str("path"); parent = r["parent"].string
            listing = r["dirs"].array.map { DirEntry(name: $0.str("name"), path: $0.str("path"), isGit: $0.flag("is_git")) }
        } catch { self.error = error.localizedDescription }
    }

    private func launch() async {
        launching = true; defer { launching = false }
        do {
            let tmux = try await model.launch(alias: alias, cwd: cwd, prompt: prompt, name: name)
            model.lastAlias = alias
            onLaunched(tmux)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
