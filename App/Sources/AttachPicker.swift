import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
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
/// menu (2026-11-05). Calls back with the picked item or nil when cancelled.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPick: (NSItemProvider?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .compatible  // HEIC arrives as JPEG, HEVC as H.264
        let p = PHPickerViewController(configuration: config)
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (NSItemProvider?) -> Void
        init(_ f: @escaping (NSItemProvider?) -> Void) { onPick = f }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onPick(results.first?.itemProvider)
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
}
