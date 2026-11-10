import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import RelayCore

/// Chat for the agent in the vault, also without a link: text, dictation (on the iPhone) and attachments wait in the
/// outbox and go out in order once the PC answers (`Outbox.deliverVault`). Each message shows whether it still waits.
struct VaultChatView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var outbox = Outbox.shared
    @StateObject private var voice = VoiceIO()
    @State private var input = ""
    @State private var files: [String] = []
    @State private var importing = false
    @State private var pickingPhoto = false
    @State private var error: String?
    @State private var dictating = false
    @State private var vocabLoaded = false
    @FocusState private var focused: Bool

    private var items: [OutItem] { outbox.items(for: VaultChat.key) }
    private var connected: Bool { model.state == .connected }
    private var target: Session? { outbox.vaultTarget.flatMap { model.session(for: $0) } }
    private var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Label(connected ? VaultChat.onlineInfo : VaultChat.offlineInfo, systemImage: connected ? "checkmark.icloud" : "icloud.slash")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("vaultInfo")
                        if let s = target {
                            Button { model.openChat = s.key } label: { Label("Zum Chat des Vault-Agenten", systemImage: "bubble.left.and.bubble.right") }
                        }
                    }
                    Section {
                        if items.isEmpty {
                            Text("Hier stehen deine Nachrichten, bis der Agent sie bekommen hat.").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(items) { i in row(i).id(i.id) }
                    }
                }
                .listStyle(.insetGrouped)
                .onChange(of: items.count) { _, _ in if let last = items.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
            }
            if let e = error {
                HStack {
                    Text(e).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button { error = nil } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(.secondary)
                }.padding(.horizontal).padding(.vertical, 4)
            }
            if !files.isEmpty { attachmentChips }
            inputBar
        }
        .navigationTitle(VaultChat.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.visibleChat = VaultChat.key
            UsageRecorder.shared.screen("vault-chat")
            outbox.sweep(seen: [])
        }
        .onDisappear {
            if model.visibleChat == VaultChat.key { model.visibleChat = nil }
            voice.stopListening(); voice.stopSpeaking(); voice.releaseAudio()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { keepFile(url) }
        }
        .sheet(isPresented: $pickingPhoto) {
            PhotoLibraryPicker { providers in
                pickingPhoto = false
                if !providers.isEmpty { Task { await keepPicked(providers) } }
            }.ignoresSafeArea()
        }
    }

    // MARK: rows

    private func row(_ i: OutItem) -> some View {
        HStack {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    if !i.text.isEmpty { Text(i.text) }
                    ForEach(i.files, id: \.self) { f in Label(VaultChat.displayName(f), systemImage: "paperclip").font(.caption) }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(i.state == .delivered ? .primary : .secondary)
                HStack(spacing: 6) {
                    if i.state == .sending || (i.state == .queued && connected) { ProgressView().controlSize(.mini) }
                    Text(OutboxLogic.status(i, connected: connected, network: model.state != .noNetwork))
                        .font(.caption2).foregroundStyle(i.state == .failed ? Color.red : Color.secondary)
                }
                if i.state == .failed {
                    HStack(spacing: 8) {
                        Button("Wiederholen") { Outbox.shared.retry(i.id) }
                        Button("Verwerfen", role: .destructive) { Outbox.shared.remove(i.id) }
                    }.font(.caption).buttonStyle(.bordered).controlSize(.mini)
                } else if i.state == .queued {
                    HStack(spacing: 8) {
                        Button("Bearbeiten") { edit(i) }
                        Button("Verwerfen", role: .destructive) { Outbox.shared.remove(i.id) }
                    }.font(.caption).buttonStyle(.bordered).controlSize(.mini)
                }
            }
        }
        .listRowSeparator(.hidden)
    }

    private func edit(_ i: OutItem) {
        input = i.text
        files = i.files
        Outbox.shared.remove(i.id, keepFiles: true)
        focused = true
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(files, id: \.self) { f in
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                        Text(VaultChat.displayName(f)).lineLimit(1)
                        Button { files.removeAll { $0 == f }; Outbox.dropFile(f) } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Anhang entfernen")
                    }
                    .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }.padding(.horizontal)
        }.padding(.vertical, 4)
    }

    // MARK: input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                Button { Task { try? await Task.sleep(nanoseconds: 350_000_000); pickingPhoto = true } } label: { Label("Fotos oder Videos", systemImage: "photo.on.rectangle") }
                Button { importing = true } label: { Label("Datei", systemImage: "doc") }
            } label: { Image(systemName: "paperclip").font(.title3) }
                .accessibilityLabel("Anhang").accessibilityIdentifier("vaultAttach")
            TextField(voice.listening ? "Ich höre zu…" : "Nachricht an den Vault-Agenten", text: $input, axis: .vertical)
                .lineLimit(1...6)
                .focused($focused)
                .padding(8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("vaultInput")
            Button { Task { await toggleDictation() } } label: {
                Image(systemName: voice.listening ? "mic.fill" : "mic").font(.title3).foregroundStyle(voice.listening ? Color.red : Color.accentColor)
            }.accessibilityLabel(voice.listening ? "Diktat beenden" : "Diktieren").accessibilityIdentifier("vaultMic")
            Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .disabled(!canSend || voice.listening)
                .accessibilityLabel("Senden").accessibilityIdentifier("vaultSend")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || !files.isEmpty else { return }
        Outbox.shared.add(key: VaultChat.key, text: t, files: files)
        UsageRecorder.shared.content("vault-chat", connected ? "gesendet" : "in postausgang", session: nil, kind: files.isEmpty ? "text" : "anhang", text: t)
        input = ""
        files = []
        error = nil
    }

    /// Diktat auf dem iPhone (geht auch ohne Verbindung, wenn die Erkennung auf dem Gerät läuft).
    private func toggleDictation() async {
        if voice.listening { voice.stopListening(); return }
        guard !dictating else { return }
        dictating = true
        defer { dictating = false }
        if let msg = await voice.authorize() { error = msg; return }
        if connected && !vocabLoaded { vocabLoaded = true; await model.loadVocab(into: voice) }
        UsageRecorder.shared.record("vault-chat", "diktat gestartet", kind: "diktat")
        var raw = ""
        do { raw = try await voice.listen() } catch { self.error = error.localizedDescription }
        voice.releaseAudio()  // Aufnahme vorbei: Musik anderer Apps läuft sofort weiter
        if !raw.isEmpty {
            UsageRecorder.shared.content("vault-chat", "diktiert", session: nil, kind: "diktat", text: raw)
            let head = input.trimmingCharacters(in: .whitespacesAndNewlines)
            input = head.isEmpty ? raw : head + " " + raw
            focused = true
        }
    }

    // MARK: attachments (kept on the phone until the PC answers)

    private func keep(name: String, data: Data) {
        guard data.count <= Attach.maxBytes else { error = "Datei ist größer als 50 MB"; return }
        guard let stored = Outbox.storeFile(name: name, data: data) else { error = "Anhang konnte nicht gespeichert werden"; return }
        files.append(stored)
        UsageRecorder.shared.record("vault-chat", "anhang gemerkt", kind: "datei", length: data.count)
    }

    private func keepFile(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { error = "Datei konnte nicht gelesen werden"; return }
        keep(name: url.lastPathComponent, data: data)
    }

    /// Mehrere Fotos und Videos auf einmal: jedes wird ein Anhang-Chip, in der Reihenfolge der Auswahl.
    private func keepPicked(_ providers: [NSItemProvider]) async {
        let (items, failed) = await StagedMedia.load(providers, stamp: Int(Date().timeIntervalSince1970))
        for m in items {
            defer { m.discard() }
            guard let data = m.bytes() else { error = "\(m.name) konnte nicht gelesen werden"; continue }
            keep(name: m.name, data: data)
        }
        if failed > 0 { error = failed == 1 ? "1 Auswahl konnte nicht geladen werden" : "\(failed) Auswahlen konnten nicht geladen werden" }
    }
}
