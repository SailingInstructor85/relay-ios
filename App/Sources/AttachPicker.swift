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
