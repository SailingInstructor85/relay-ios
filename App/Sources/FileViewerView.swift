import SwiftUI
import PDFKit
import QuickLook
import RelayCore

/// Full-screen view of a Desktop file: image with zoom, PDF, text and code, markdown, anything else through Quick Look.
struct FileViewerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let start: RemoteRef
    /// Folder used to resolve relative links inside a markdown file.
    var base: String?

    @State private var ref: RemoteRef
    @State private var url: URL?
    @State private var progress = 0.0
    @State private var error: String?
    @State private var next: RemoteRef?
    @State private var copied = false

    init(start: RemoteRef, base: String? = nil) {
        self.start = start; self.base = base
        _ref = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(ref.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if let url { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
                        Menu {
                            Button { UIPasteboard.general.string = ref.path; copied = true } label: { Label("Pfad kopieren", systemImage: "doc.on.doc") }
                            if let url { ShareLink(item: url) { Label("Teilen oder sichern", systemImage: "square.and.arrow.down") } }
                            Section(ref.path) { if ref.size >= 0 { Text(FileKinds.sizeLabel(ref.size)) } }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
        }
        .task { await load() }
        .sheet(item: $next) { r in FileViewerView(start: r, base: (r.path as NSString).deletingLastPathComponent).environmentObject(model) }
        .overlay(alignment: .bottom) {
            if copied {
                Text("Pfad kopiert").font(.footnote).padding(8).background(.thinMaterial, in: Capsule()).padding(.bottom, 24)
                    .task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let error {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text(error).multilineTextAlignment(.center).textSelection(.enabled)
                Button("Noch einmal") { Task { await load() } }.buttonStyle(.bordered)
            }.padding()
        } else if let url {
            switch ref.mode {
            case .image: ZoomableImage(url: url)
            case .pdf: PDFKitView(url: url).ignoresSafeArea(edges: .bottom)
            case .text: TextFileBody(url: url)
            case .markdown: MarkdownFileBody(url: url, base: (ref.path as NSString).deletingLastPathComponent, onFile: { next = $0 })
            case .other: QuickLookView(url: url).ignoresSafeArea(edges: .bottom)
            }
        } else {
            VStack(spacing: 12) {
                ProgressView(value: progress > 0 ? progress : nil)
                    .progressViewStyle(.linear).frame(maxWidth: 240)
                Text(progress > 0 ? "Lade \(Int(progress * 100)) %" : "Lade…").font(.footnote).foregroundStyle(.secondary)
                if ref.size > 0 { Text("\(ref.name) · \(FileKinds.sizeLabel(ref.size))").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func load() async {
        error = nil; url = nil; progress = 0
        do {
            if ref.mtime == 0 || ref.size < 0 { ref = try await FileStore.shared.info(ref.path) }
            url = try await FileStore.shared.local(ref) { p in progress = p }
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: bodies

struct ZoomableImage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var scale = 1.0
    @State private var baseScale = 1.0
    @State private var offset = CGSize.zero
    @State private var baseOffset = CGSize.zero

    var body: some View {
        GeometryReader { geo in
            if let image {
                let fit = fitted(image.size, in: geo.size)
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { v in
                                scale = min(max(baseScale * v, 1), ZoomMath.max)
                                offset = clamp(offset, fit: fit, view: geo.size)
                            }
                            .onEnded { _ in
                                baseScale = scale
                                if scale <= 1.01 { reset() } else { baseOffset = offset }
                            }
                            .simultaneously(with: DragGesture()
                                .onChanged { v in
                                    guard scale > 1 else { return }
                                    offset = clamp(CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height), fit: fit, view: geo.size)
                                }
                                .onEnded { _ in baseOffset = offset })
                    )
                    .onTapGesture(count: 2) {
                        withAnimation { if scale > 1 { reset() } else { scale = ZoomMath.doubleTap; baseScale = scale } }
                    }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemBackground))
        .task { image = await Task.detached { UIImage(contentsOfFile: url.path) }.value }
    }

    private func reset() { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }

    private func fitted(_ img: CGSize, in view: CGSize) -> CGSize {
        guard img.width > 0, img.height > 0 else { return view }
        let s = min(view.width / img.width, view.height / img.height)
        return CGSize(width: img.width * s, height: img.height * s)
    }

    private func clamp(_ o: CGSize, fit: CGSize, view: CGSize) -> CGSize {
        CGSize(width: ZoomMath.clamp(o.width, fitted: fit.width, view: view.width, scale: scale),
               height: ZoomMath.clamp(o.height, fitted: fit.height, view: view.height, scale: scale))
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

struct TextFileBody: View {
    let url: URL
    @State private var text = ""
    @State private var truncated = false
    private let limit = 600_000

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                if truncated { Text("Gekürzt: nur der Anfang der Datei wird gezeigt.").font(.caption).foregroundStyle(.secondary) }
            }.padding()
        }
        .toolbar { ToolbarItem(placement: .bottomBar) { Button { UIPasteboard.general.string = text } label: { Label("Kopieren", systemImage: "doc.on.doc") } } }
        .task {
            let u = url, lim = limit
            let r: (String, Bool) = await Task.detached {
                guard let h = try? FileHandle(forReadingFrom: u) else { return ("Datei konnte nicht gelesen werden.", false) }
                defer { try? h.close() }
                let d = (try? h.read(upToCount: lim + 1)) ?? Data()
                let cut = d.count > lim
                return (String(decoding: cut ? d.prefix(lim) : d, as: UTF8.self), cut)
            }.value
            text = r.0; truncated = r.1
        }
    }
}

struct MarkdownFileBody: View {
    let url: URL
    let base: String
    let onFile: (RemoteRef) -> Void
    @EnvironmentObject var model: AppModel
    @State private var text = ""

    var body: some View {
        ScrollView {
            MarkdownText(text: text).padding()
        }
        .environment(\.openURL, OpenURLAction { link in
            LinkRouter.open(link.absoluteString, base: base, onFile: onFile)
            return .handled
        })
        .task {
            let u = url
            text = await Task.detached { (try? String(contentsOf: u, encoding: .utf8)) ?? "Datei konnte nicht gelesen werden." }.value
        }
    }
}

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ c: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(_ u: URL) { url = u }
        func numberOfPreviewItems(in c: QLPreviewController) -> Int { 1 }
        func previewController(_ c: QLPreviewController, previewItemAt i: Int) -> QLPreviewItem { url as NSURL }
    }
}
