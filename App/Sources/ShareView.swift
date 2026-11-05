import SwiftUI
import RelayCore

/// "In Relay öffnen" (no Share Extension): a file opened from Files, Mail or another app arrives through `onOpenURL`.
/// The sheet asks which session gets it, uploads the files and puts their paths into that session.
struct ShareView: View {
    @EnvironmentObject var model: AppModel
    let files: [URL]
    let onDone: () -> Void

    @State private var query = ""
    @State private var chosen: String?
    @State private var message = ""
    @State private var sending = false
    @State private var progress = ""
    @State private var error: String?
    @State private var askForce = false

    private struct Item: Identifiable { let id: URL; let name: String; let size: Int }

    private var items: [Item] {
        files.enumerated().map { n, u in
            let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            return Item(id: u, name: ShareLogic.cleanName(u.lastPathComponent, ext: u.pathExtension, n: n + 1), size: size)
        }
    }

    private var targets: [Session] { ShareLogic.targets(Array(model.sessions.values), lastKey: model.lastOpenedKey, query: query) }

    var body: some View {
        NavigationStack {
            List {
                Section("Dateien") {
                    ForEach(items) { i in
                        HStack {
                            Image(systemName: "doc")
                            Text(i.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(ShareLogic.sizeLabel(i.size)).font(.caption).foregroundStyle(i.size > ShareLogic.maxBytes ? .red : .secondary)
                        }
                    }
                }
                Section("Nachricht (optional)") {
                    TextField("Was soll die Sitzung damit tun?", text: $message, axis: .vertical).lineLimit(1...5)
                }
                Section("In welche Sitzung senden?") {
                    TextField("Sitzung suchen", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if targets.isEmpty {
                        Text(model.state == .connected ? "Keine laufende Sitzung gefunden" : "Nicht verbunden: \(model.connLabel)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(targets) { s in
                        Button { chosen = s.key } label: {
                            HStack(spacing: 10) {
                                StateDot(state: s.shownState)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.name).lineLimit(1)
                                    Text("\(s.alias) · \(s.folder)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if chosen == s.key { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }.foregroundStyle(.primary)
                    }
                }
                if !progress.isEmpty { Section { Text(progress).font(.footnote) } }
                if let e = error { Section { Text(e).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("In Relay öffnen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { onDone() }.disabled(sending) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sende…" : "Senden") { Task { await send(force: false) } }
                        .disabled(chosen == nil || sending || !ShareLogic.canSend(files: files.count, text: nil, message: message))
                }
            }
            .confirmationDialog("Die Sitzung arbeitet gerade.", isPresented: $askForce, titleVisibility: .visible) {
                Button("Trotzdem senden") { Task { await send(force: true) } }
                Button("Abbrechen", role: .cancel) {}
            }
            .onAppear { if chosen == nil { chosen = targets.first?.key } }
        }
    }

    private func send(force: Bool) async {
        guard let key = chosen, let s = model.session(for: key) else { return }
        sending = true; error = nil
        defer { sending = false }
        // wait a moment for the link when the app was just started by the share
        for _ in 0..<40 where model.state != .connected { try? await Task.sleep(nanoseconds: 250_000_000) }
        guard model.state == .connected else { error = "Nicht verbunden: \(model.connLabel)"; return }
        do {
            var paths: [String] = []
            for (n, f) in items.enumerated() {
                guard f.size <= ShareLogic.maxBytes else { throw RelayError("\(f.name) ist größer als 50 MB") }
                progress = "Lade \(n + 1)/\(items.count) \(f.name) hoch…"
                let ok = f.id.startAccessingSecurityScopedResource()
                defer { if ok { f.id.stopAccessingSecurityScopedResource() } }
                let url = f.id
                var name = f.name
                var data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
                (name, data) = await Task.detached(priority: .userInitiated) { [nm = name, d = data] in AttachPrep.prepared(name: nm, data: d) }.value
                let label = name
                paths.append(try await model.upload(name: label, data: data) { p in
                    Task { @MainActor in progress = "Lade \(n + 1)/\(items.count) \(label) hoch… \(Int(p * 100)) %" }
                })
            }
            progress = "Sende an \(s.name)…"
            try await model.send(s, text: ShareLogic.body(message: message, paths: paths, text: nil), force: force)
            progress = ""
            model.openChat = s.key
            onDone()
        } catch {
            progress = ""
            if !force, let e = error as? RelayError, e.remote, OutboxLogic.isBusyRefusal(e.message) { askForce = true }
            else { self.error = error.localizedDescription }
        }
    }
}
