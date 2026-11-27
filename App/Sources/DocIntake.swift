import SwiftUI
import UIKit
import UniformTypeIdentifiers
import RelayCore

/// Fotos und Dokumente annehmen, gemeinsam für den Jarvis-Chat und das Antwortfeld einer Rückfrage: Dateien aus der
/// Dateien-App, Fotos, Screenshots und Videos aus der Mediathek, Kamera, Bild aus der Zwischenablage. Was hier
/// herauskommt, ist ein `JarvisDoc` mit Vorschau; hochgeladen wird erst beim Senden (`upload`).
enum DocIntake {
    struct Loaded {
        var docs: [JarvisDoc] = []
        var problems: [String] = []
        /// Was dem Nutzer gezeigt wird, wenn etwas nicht ging; nil, wenn alles geladen ist.
        var error: String? { problems.isEmpty ? nil : problems.joined(separator: ", ") }
    }

    /// Dateien aus der Dateien-App: sofort lesen (der Zugriff gilt nur jetzt).
    static func files(_ urls: [URL]) -> Loaded {
        var r = Loaded()
        for url in urls {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { r.problems.append(JarvisDocs.unreadable(name)); continue }
            guard data.count <= JarvisDocs.maxBytes else { r.problems.append(JarvisDocs.tooBig(name)); continue }
            // Bilddateien (zum Beispiel ein gesicherter Screenshot) zeigen wie Fotos eine Vorschau
            r.docs.append(JarvisDoc(name: name, data: data, media: nil, preview: JarvisDocs.isPicture(name) ? AttachPrep.thumbnail(data) : nil))
        }
        return r
    }

    /// Fotos und Videos aus der Mediathek (Fotos schon auf 2048 px verkleinert, Videos bleiben in ihrer Datei).
    static func picked(_ providers: [NSItemProvider]) async -> Loaded {
        let (items, failed) = await StagedMedia.load(providers, stamp: Int(Date().timeIntervalSince1970))
        var r = Loaded()
        for m in items {
            if m.size() > JarvisDocs.maxBytes {
                m.discard()
                r.problems.append(JarvisDocs.tooBig(m.name))
            } else {
                r.docs.append(JarvisDoc(name: m.name, data: nil, media: m))
            }
        }
        if failed > 0 { r.problems.append(failed == 1 ? "1 Auswahl konnte nicht geladen werden" : "\(failed) Auswahlen konnten nicht geladen werden") }
        return r
    }

    static func camera(_ jpeg: Data) async -> Loaded {
        await image(name: "kamera-\(Int(Date().timeIntervalSince1970)).jpg", data: jpeg, mime: "image/jpeg")
    }

    /// Ein Bild aus der Zwischenablage, zum Beispiel ein eben kopierter Screenshot.
    @MainActor
    static func clipboard() async -> Loaded {
        guard let img = UIPasteboard.general.image, let d = img.pngData() else { return Loaded(problems: ["Kein Bild in der Zwischenablage"]) }
        return await image(name: JarvisDocs.clipboardName(stamp: Int(Date().timeIntervalSince1970)), data: d, mime: "image/png")
    }

    /// Ein Bild als Bytes (Kamera, Zwischenablage): wie Fotos aus der Mediathek auf 2048 px verkleinert, mit Vorschau.
    static func image(name: String, data: Data, mime: String) async -> Loaded {
        let p: (name: String, data: Data, thumb: UIImage?) = await Task.detached(priority: .userInitiated) { () -> (name: String, data: Data, thumb: UIImage?) in
            let prep = AttachPrep.prepared(name: name, data: data, mime: mime)
            return (prep.name, prep.data, AttachPrep.thumbnail(prep.data))
        }.value
        guard p.data.count <= JarvisDocs.maxBytes else { return Loaded(problems: [JarvisDocs.tooBig(p.name)]) }
        return Loaded(docs: [JarvisDoc(name: p.name, data: p.data, media: nil, preview: p.thumb)])
    }

    /// Lädt alle an den PC und gibt die Pfade dort zurück, in derselben Reihenfolge. `progress`: „Lade 1/2 … hoch…“.
    @MainActor
    static func upload(_ docs: [JarvisDoc], model: AppModel, progress: (String) -> Void) async throws -> [String] {
        var paths: [String] = []
        for (i, d) in docs.enumerated() {
            progress(JarvisDocs.progress(index: i, count: docs.count, name: d.name))
            guard let data = d.bytes() else { throw RelayError(JarvisDocs.unreadable(d.name)) }
            guard data.count <= JarvisDocs.maxBytes else { throw RelayError(JarvisDocs.tooBig(d.name)) }
            paths.append(try await model.upload(name: d.name, data: data))
        }
        return paths
    }
}

/// Die angehängten Fotos und Dokumente über einer Eingabe, Bilder mit Vorschau, jedes mit einem Knopf zum Herausnehmen.
struct DocStrip: View {
    let docs: [JarvisDoc]
    var disabled = false
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(docs) { d in
                    HStack(spacing: 4) {
                        if let t = d.thumb {
                            Image(uiImage: t).resizable().scaledToFill().frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Image(systemName: JarvisDocs.symbol(d.name))
                        }
                        Text(d.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: 180)
                        Button { onRemove(d.id) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).disabled(disabled)
                            .accessibilityLabel("Aus der Auswahl nehmen")
                    }
                    .font(.footnote)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }.padding(.horizontal)
        }
    }
}

/// Antwortfeld einer Rückfrage mit Büroklammer und Mikrofon wie im Jarvis-Chat (Martin, 25.11.2026): links die
/// Büroklammer (Mediathek mit Screenshots, Kamera, Zwischenablage, Dateien-App), in der Mitte das Feld, rechts das
/// Mikrofon. Das Mikrofon nutzt Relays eigene Spracherkennung auf dem iPhone mit dem Vokabular des PCs (`VoiceIO`)
/// und legt das Gesprochene ins Feld; gesendet wird erst mit „Antworten“. Die Anhänge stehen als Marken über dem
/// Feld und gehen beim Senden an den PC (`DocIntake.upload`), ihre Pfade kommen in die Antwort
/// (`Rueckfrage.answerBody`). Kennungen für die UI-Tests: `<prefix>Answer`, `<prefix>Attach`, `<prefix>Mic`.
struct AnswerComposer: View {
    @EnvironmentObject var model: AppModel
    let placeholder: String
    @Binding var text: String
    @Binding var docs: [JarvisDoc]
    @Binding var error: String?
    var focused: FocusState<Bool>.Binding
    let prefix: String
    /// Name der Ansicht im Nutzungsprotokoll.
    let screen: String
    /// Unter diesem Schlüssel bleibt der Text als Entwurf erhalten (`Drafts.question`), auch das, was ein laufendes
    /// Diktat bis jetzt erkannt hat; nil = nicht sichern.
    var draftKey: String? = nil

    @StateObject private var voice = VoiceIO()
    @State private var dictating = false
    @State private var vocabLoaded = false
    @State private var importing = false
    @State private var pickingPhoto = false
    @State private var camera = false
    @State private var loading = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !loading.isEmpty { Text(loading).font(.caption).foregroundStyle(.secondary) }
            if voice.listening {
                Text(voice.partial.isEmpty ? "Ich höre…" : voice.partial).font(.callout).italic().foregroundStyle(.secondary)
                    .accessibilityIdentifier(prefix + "Heard")
            }
            if !docs.isEmpty {
                DocStrip(docs: docs) { remove($0) }.accessibilityIdentifier(prefix + "Docs")
            }
            HStack(alignment: .center, spacing: 8) {
                attachMenu
                TextField(voice.listening ? "Ich höre zu…" : placeholder, text: $text, axis: .vertical).lineLimit(1...4)
                    .font(RelayFont.bodyLarge)
                    .focused(focused)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RelayColor.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: RelayRadius.option, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: RelayRadius.option, style: .continuous).strokeBorder(RelayColor.outlineVariant, lineWidth: 1) }
                    .accessibilityIdentifier(prefix + "Answer")
                Button { Task { await toggleDictation() } } label: {
                    Image(systemName: voice.listening ? "mic.fill" : "mic").font(.title3)
                        .foregroundStyle(voice.listening ? Color.red : Color.accentColor)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(voice.listening ? "Diktat beenden" : "Diktieren").accessibilityIdentifier(prefix + "Mic")
            }
        }
        .onDisappear { voice.stopListening(); voice.releaseAudio() }
        .keepsDraft(draftKey, text: $text, heard: voice.listening ? voice.partial : "")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { took(DocIntake.files(urls), kind: "datei") }
        }
        .sheet(isPresented: $pickingPhoto) {
            PhotoLibraryPicker { providers in
                pickingPhoto = false
                if !providers.isEmpty { Task { await addPicked(providers) } }
            }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { img in
                camera = false
                if let img, let d = img.jpegData(compressionQuality: 0.95) { Task { await addCamera(d) } }
            }.ignoresSafeArea()
        }
    }

    /// Dieselben Einträge in derselben Reihenfolge wie im Jarvis-Chat, Fotos (mit Screenshots aus der Mediathek) zuerst.
    private var attachMenu: some View {
        Menu {
            // Eine Auswahl in einem Menü öffnet sich auf iOS nicht; einen Moment später ist das Menü zu.
            Button { Task { try? await Task.sleep(nanoseconds: 350_000_000); pickingPhoto = true } } label: { Label("Fotos, Screenshots oder Videos", systemImage: "photo.on.rectangle") }
            if CameraPicker.available { Button { camera = true } label: { Label("Kamera", systemImage: "camera") } }
            if UIPasteboard.general.hasImages { Button { Task { await addClipboard() } } label: { Label("Bild aus Zwischenablage", systemImage: "doc.on.clipboard") } }
            Button { importing = true } label: { Label("Datei", systemImage: "doc") }
        } label: {
            Image(systemName: "paperclip").font(.title3).frame(width: 36, height: 36)
        }
        .accessibilityLabel("Fotos oder Dokumente anhängen").accessibilityIdentifier(prefix + "Attach")
    }

    private func took(_ r: DocIntake.Loaded, kind: String) {
        if !r.docs.isEmpty {
            docs += r.docs
            UsageRecorder.shared.record(screen, "dokument angehängt", kind: kind, length: r.docs.count)
        }
        if let e = r.error { error = e }
    }

    private func addPicked(_ providers: [NSItemProvider]) async {
        loading = providers.count > 1 ? "Lade \(providers.count) Fotos aus der Mediathek…" : "Lade Auswahl…"
        let r = await DocIntake.picked(providers)
        loading = ""
        took(r, kind: "foto")
    }

    private func addCamera(_ jpeg: Data) async {
        let r = await DocIntake.camera(jpeg)
        took(r, kind: "foto")
    }

    private func addClipboard() async {
        let r = await DocIntake.clipboard()
        took(r, kind: "zwischenablage")
    }

    private func remove(_ id: UUID) {
        docs.first(where: { $0.id == id })?.discard()
        docs.removeAll { $0.id == id }
    }

    /// Mikrofon: hört zu, bis eine Pause entsteht oder der Knopf noch einmal getippt wird, und legt die Worte ins Feld.
    private func toggleDictation() async {
        if voice.listening { voice.stopListening(); return }
        guard !dictating else { return }
        dictating = true
        defer { dictating = false }
        if let msg = await voice.authorize() { error = msg; return }
        if model.state == .connected && !vocabLoaded { vocabLoaded = true; await model.loadVocab(into: voice) }
        UsageRecorder.shared.record(screen, "diktat gestartet", kind: "diktat")
        var heard = ""
        do { heard = try await voice.listen() } catch {
            UsageRecorder.shared.record(screen, "fehler", kind: "diktat", error: error.localizedDescription)
            self.error = error.localizedDescription
        }
        voice.releaseAudio()  // Aufnahme vorbei: Musik anderer Apps läuft sofort weiter
        if !heard.isEmpty {
            UsageRecorder.shared.content(screen, "diktiert", session: nil, kind: "diktat", text: heard)
            text = Rueckfrage.dictated(field: text, heard: heard)
        }
    }
}
