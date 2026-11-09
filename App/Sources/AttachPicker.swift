import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import RelayCore

/// The system camera (UIImagePickerController, no extension needed). Calls back with the shot or nil when cancelled.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(_ f: @escaping (UIImage?) -> Void) { onImage = f }
        func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ p: UIImagePickerController) { onImage(nil) }
    }
}

/// The photo library (PHPickerViewController, runs out of process, needs no permission), shown in a sheet.
/// Replaces SwiftUI's `.photosPicker(isPresented:)`, which on the iPhone did not open when triggered from the attach
/// menu (2026-11-05). Several photos and videos can be picked at once (since 0.3.13, in the order tapped); calls back
/// with the picked items, empty when cancelled.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPick: ([NSItemProvider]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 0  // no limit
        config.selection = .ordered  // numbers in the picker, items arrive in that order
        config.preferredAssetRepresentationMode = .compatible  // HEIC arrives as JPEG, HEVC as H.264
        let p = PHPickerViewController(configuration: config)
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([NSItemProvider]) -> Void
        init(_ f: @escaping ([NSItemProvider]) -> Void) { onPick = f }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onPick(results.map(\.itemProvider))
        }
    }
}

/// What the photo library handed over: a video as a temp file, or an image's bytes.
enum PickedMedia {
    case movie(URL)
    case image(Data)

    static func load(_ p: NSItemProvider) async throws -> PickedMedia {
        if p.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return .movie(try await withCheckedThrowingContinuation { c in
                _ = p.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, err in
                    // The file is only valid inside this callback: copy it out first.
                    guard let url else { c.resume(throwing: err ?? RelayErrorText("Video konnte nicht geladen werden")); return }
                    let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
                    do { try FileManager.default.copyItem(at: url, to: dest); c.resume(returning: dest) } catch { c.resume(throwing: error) }
                }
            })
        }
        return .image(try await withCheckedThrowingContinuation { c in
            _ = p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, err in
                if let data { c.resume(returning: data) } else { c.resume(throwing: err ?? RelayErrorText("Foto konnte nicht geladen werden")) }
            }
        })
    }
}

/// A video from the photo picker, copied to a temp file (not into memory) until it is uploaded.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in SentTransferredFile(m.url) } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(received.file.lastPathComponent)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

enum AttachPrep {
    /// Photos with a long edge above 2048 px are scaled down to 2048 and re-encoded as JPEG (0.85); GIFs and non-images
    /// go as they are. Uses the image decoder's own thumbnail (upright, without holding the full bitmap).
    static func prepared(name: String, data: Data, mime: String? = nil) -> (name: String, data: Data) {
        guard Attach.isImage(name, mime: mime), !Attach.isGif(name, mime: mime),
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              Attach.needsResize(name: name, mime: mime, width: w, height: h) else { return (name, data) }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: Attach.outEdge]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
              let jpg = UIImage(cgImage: cg).jpegData(compressionQuality: Attach.quality) else { return (name, data) }
        return (Attach.jpegName(name), jpg)
    }

    /// A small preview (long edge 240 px) for the selection strip.
    static func thumbnail(_ data: Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 240]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

/// A photo or video from the library that waits in the preview strip above the input until it is uploaded together
/// with the others. Photos are already scaled down (2048 px) so a long selection does not hold full-size images.
struct StagedMedia: Identifiable {
    let id = UUID()
    let name: String
    let video: Bool
    /// Photo bytes (prepared); nil for a video, which stays in its temp file until the upload.
    let data: Data?
    let movie: URL?
    let thumb: UIImage?
    let mime: String?

    /// Loads the picked items one after another; items that fail are skipped and reported in `failed`.
    static func load(_ providers: [NSItemProvider], stamp: Int) async -> (items: [StagedMedia], failed: Int) {
        var out: [StagedMedia] = []
        var failed = 0
        let count = providers.count
        for (i, p) in providers.enumerated() {
            guard let media = try? await PickedMedia.load(p) else { failed += 1; continue }
            switch media {
            case .movie(let url):
                let name = PhotoBatch.name(video: true, stamp: stamp, index: i, count: count, ext: url.pathExtension)
                let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 240, height: 240)
                let thumb = (try? await gen.image(at: .zero)).map { UIImage(cgImage: $0.image) }
                out.append(StagedMedia(name: name, video: true, data: nil, movie: url, thumb: thumb, mime: nil))
            case .image(let raw):
                let prepared: (name: String, data: Data, mime: String?, thumb: UIImage?) = await Task.detached(priority: .userInitiated) { () -> (name: String, data: Data, mime: String?, thumb: UIImage?) in
                    // The name follows the bytes (with .compatible iOS hands over JPEG for a HEIC original).
                    let type = CGImageSourceCreateWithData(raw as CFData, nil).flatMap { CGImageSourceGetType($0) }.flatMap { UTType($0 as String) }
                    let name = PhotoBatch.name(video: false, stamp: stamp, index: i, count: count, ext: type?.preferredFilenameExtension ?? "jpg")
                    let prep = AttachPrep.prepared(name: name, data: raw, mime: type?.preferredMIMEType)
                    let mime: String? = prep.name == name ? type?.preferredMIMEType : "image/jpeg"
                    return (prep.name, prep.data, mime, AttachPrep.thumbnail(prep.data))
                }.value
                out.append(StagedMedia(name: prepared.name, video: false, data: prepared.data, movie: nil, thumb: prepared.thumb, mime: prepared.mime))
            }
        }
        return (out, failed)
    }

    /// The bytes to upload (videos are read from their temp file only now).
    func bytes() -> Data? { data ?? movie.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) } }

    func size() -> Int { data?.count ?? movie.flatMap { (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize } ?? 0 }

    /// Removes the temp file of a video (after the upload or when the item is taken out of the strip).
    func discard() { if let movie { try? FileManager.default.removeItem(at: movie) } }
}

/// The picked photos and videos above the input: thumbnails with a remove button each, "N Fotos hochladen" and
/// "Verwerfen". Nothing goes up before the button is tapped.
struct StagedMediaStrip: View {
    let items: [StagedMedia]
    let busy: Bool
    let onRemove: (UUID) -> Void
    let onUpload: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { m in
                        ZStack(alignment: .topTrailing) {
                            Group {
                                if let t = m.thumb { Image(uiImage: t).resizable().scaledToFill() }
                                else { Image(systemName: m.video ? "video" : "photo").font(.title2).foregroundStyle(.secondary) }
                            }
                            .frame(width: 64, height: 64)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .bottomLeading) {
                                if m.video { Image(systemName: "video.fill").font(.caption2).foregroundStyle(.white).padding(4).shadow(radius: 2) }
                            }
                            if !busy {
                                Button { onRemove(m.id) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.body).symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .buttonStyle(.plain).padding(2)
                                .accessibilityLabel("Aus der Auswahl nehmen")
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(m.name)
                    }
                }.padding(.horizontal)
            }
            HStack(spacing: 8) {
                let videos = items.filter(\.video).count
                Button { onUpload() } label: {
                    Label(PhotoBatch.uploadTitle(photos: items.count - videos, videos: videos), systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderedProminent).controlSize(.small).disabled(busy)
                .accessibilityIdentifier("stagedUpload")
                Button("Verwerfen", role: .destructive) { onDiscard() }
                    .buttonStyle(.bordered).controlSize(.small).disabled(busy)
                    .accessibilityIdentifier("stagedDiscard")
                Spacer()
            }.padding(.horizontal)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("stagedMedia")
    }
}
