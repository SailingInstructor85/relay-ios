import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import RelayCore

/// Share and save actions for a Desktop file (the file is fetched first).
@MainActor
enum FileActions {
    private static var topController: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.keyWindow?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }

    static func share(_ ref: RemoteRef, onError: @escaping (String) -> Void) {
        Task {
            do {
                let url = try await FileStore.shared.local(ref)
                let v = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                topController?.present(v, animated: true)
            } catch { onError(error.localizedDescription) }
        }
    }

    /// "In Dateien sichern": the system export picker.
    static func save(_ ref: RemoteRef, onError: @escaping (String) -> Void) {
        Task {
            do {
                let url = try await FileStore.shared.local(ref)
                let p = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                topController?.present(p, animated: true)
            } catch { onError(error.localizedDescription) }
        }
    }
}

/// A file of a message as a chip: icon or thumbnail, name, size. Tap opens the viewer, long press offers share, save, copy path.
struct FileChip: View {
    let ref: RemoteRef
    var onOpen: (RemoteRef) -> Void
    var onError: (String) -> Void = { _ in }
    @State private var thumb: UIImage?

    var body: some View {
        Button { onOpen(ref) } label: {
            HStack(spacing: 10) {
                Group {
                    if let thumb {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        Image(systemName: ref.symbol).font(.title3).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.name).font(.footnote.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    let cap = FileKinds.sizeLabel(ref.size)
                    if !cap.isEmpty { Text(cap).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: 320, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { FileActions.share(ref, onError: onError) } label: { Label("Teilen", systemImage: "square.and.arrow.up") }
            Button { FileActions.save(ref, onError: onError) } label: { Label("Sichern", systemImage: "square.and.arrow.down") }
            Button { UIPasteboard.general.string = ref.path } label: { Label("Pfad kopieren", systemImage: "doc.on.doc") }
        }
        .task(id: ref.path) {
            if ref.isImage && ref.size != 0 { thumb = await FileStore.shared.thumb(ref, px: 192) }
        }
        .accessibilityLabel("Datei \(ref.name)")
    }
}

/// Reads a message aloud with an installed on-device voice.
@MainActor
final class SpeechOut: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speaking = false
    private let synth = AVSpeechSynthesizer()

    override init() { super.init(); synth.delegate = self }

    func toggle(_ markdown: String) {
        if speaking { stop(); return }
        let text = VoiceIO.speakable(markdown)
        guard text.rangeOfCharacter(from: .alphanumerics) != nil else { return }
        let u = VoiceIO.utterance(text)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        speaking = true
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate); speaking = false }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in self.speaking = false } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { Task { @MainActor in self.speaking = false } }
}

/// Selectable full-screen text (UITextView: handles, select all, copy).
struct SelectableText: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.font = UIFont.preferredFont(forTextStyle: .body)
        v.adjustsFontForContentSizeCategory = true
        v.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        v.text = text
        return v
    }
    func updateUIView(_ v: UITextView, context: Context) { if v.text != text { v.text = text } }
}

/// Long press on a message: copy, select text, read aloud, its links and files.
struct MessageMenu: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let message: TMessage
    let base: String?
    let onFile: (RemoteRef) -> Void

    @StateObject private var speech = SpeechOut()
    @State private var copied = ""
    @State private var error: String?

    private var links: [FoundLink] { Array(Links.extract(message.text).prefix(30)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { UIPasteboard.general.string = message.text; flash("Kopiert") } label: { Label("Kopieren", systemImage: "doc.on.doc") }
                    NavigationLink { SelectableText(text: message.text).navigationTitle("Text auswählen").navigationBarTitleDisplayMode(.inline) } label: {
                        Label("Text auswählen", systemImage: "selection.pin.in.out")
                    }
                    Button { speech.toggle(message.text) } label: {
                        Label(speech.speaking ? "Vorlesen beenden" : "Vorlesen", systemImage: speech.speaking ? "speaker.slash" : "speaker.wave.2")
                    }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
                if !links.isEmpty {
                    Section("Links") {
                        ForEach(links, id: \.target) { l in
                            Button { open(l.target) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.label).lineLimit(2)
                                    if l.label != l.target { Text(l.target).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                                }
                            }
                            .contextMenu {
                                Button { UIPasteboard.general.string = l.target; flash("Link kopiert") } label: { Label("Link kopieren", systemImage: "doc.on.doc") }
                            }
                            .swipeActions { Button { UIPasteboard.general.string = l.target; flash("Link kopiert") } label: { Label("Kopieren", systemImage: "doc.on.doc") }.tint(.blue) }
                        }
                    }
                }
                if !message.files.isEmpty {
                    Section("Dateien") {
                        ForEach(message.files, id: \.path) { f in
                            FileChip(ref: RemoteRef(f), onOpen: { r in dismiss(); onFile(r) }, onError: { error = $0 })
                        }
                    }
                }
            }
            .navigationTitle(copied.isEmpty ? "Nachricht" : copied)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { speech.stop() }
    }

    private func open(_ raw: String) {
        LinkRouter.open(raw, base: base, onFile: { r in dismiss(); onFile(r) }, onError: { error = $0 })
    }

    private func flash(_ t: String) {
        copied = t
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = "" }
    }
}
