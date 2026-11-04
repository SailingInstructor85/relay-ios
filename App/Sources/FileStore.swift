import Foundation
import UIKit
import CryptoKit
import RelayCore

/// A file on the Desktop as the chat knows it (from `files[]`, `file_info` or a link).
struct RemoteRef: Identifiable, Hashable {
    var id: String { path }
    let path: String
    var name: String
    var size: Int
    var mime: String
    var kind: String
    var mtime: Double

    init(path: String, name: String? = nil, size: Int = -1, mime: String = "", kind: String = "", mtime: Double = 0) {
        self.path = path
        self.name = name ?? (path as NSString).lastPathComponent
        self.size = size; self.mime = mime; self.kind = kind; self.mtime = mtime
    }

    init(_ f: RemoteFile) { self.init(path: f.path, name: f.name, size: f.size, mime: f.mime, kind: f.kind) }

    static func from(_ o: JSON) -> RemoteRef? {
        let p = o.str("path"); guard !p.isEmpty else { return nil }
        return RemoteRef(path: p, name: o.str("name", (p as NSString).lastPathComponent), size: o["size"].int ?? -1,
                         mime: o.str("mime"), kind: o.str("kind"), mtime: o.num("mtime"))
    }

    var mode: FileKinds.Mode { FileKinds.mode(name, mime: mime, kind: kind) }
    var symbol: String { FileKinds.symbol(FileKinds.icon(name, mime: mime, kind: kind)) }
    var isImage: Bool { FileKinds.isImage(name, mime: mime, kind: kind) }
}

/// Limits concurrent thumbnail requests (a chat full of images must not queue dozens of rpcs).
private actor Gate {
    private var free: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ n: Int) { free = n }
    func enter() async {
        if free > 0 { free -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func leave() {
        if waiters.isEmpty { free += 1 } else { waiters.removeFirst().resume() }
    }
}

/// Fetches files from the Desktop through `file_info` and `file_get` and keeps them in the Caches folder
/// (`relay-files/<hash(path)>-<mtime>/<name>`, a changed mtime loads again).
@MainActor
final class FileStore {
    static let shared = FileStore()
    private let maxBytes = 100 * 1024 * 1024
    private let gate = Gate(3)
    private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<URL, Error>] = [:]
    private var thumbInflight: [String: Task<UIImage?, Never>] = [:]

    private var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("relay-files", isDirectory: true)
    }

    private static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    func info(_ path: String) async throws -> RemoteRef {
        let r = try await AppModel.shared.rpc("file_info", ["path": .string(path)], timeout: 20)
        guard let ref = RemoteRef.from(r) else { throw RelayErrorText("Datei nicht gefunden") }
        return ref
    }

    /// The thumbnail of an image (long edge `px`), from memory, disk or the Desktop; nil when it can't be had.
    func thumb(_ ref: RemoteRef, px: Int) async -> UIImage? {
        let k = Self.hash("\(ref.path)\n\(ref.size)\n\(px)")
        if let m = memory.object(forKey: k as NSString) { return m }
        let file = root.appendingPathComponent("thumbs", isDirectory: true).appendingPathComponent(k + ".jpg")
        if let d = try? Data(contentsOf: file), let img = UIImage(data: d) { memory.setObject(img, forKey: k as NSString); return img }
        if let t = thumbInflight[k] { return await t.value }
        let t = Task { @MainActor () -> UIImage? in
            await self.gate.enter()
            defer { let g = self.gate; Task { await g.leave() } }
            guard let r = try? await AppModel.shared.rpc("file_get", ["path": .string(ref.path), "thumb": .number(Double(px))], timeout: 40),
                  let data = Data(base64Encoded: r.str("data_b64")), let img = UIImage(data: data) else { return nil }
            if r.flag("thumb") {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file)
            }
            self.memory.setObject(img, forKey: k as NSString)
            return img
        }
        thumbInflight[k] = t
        let img = await t.value
        thumbInflight[k] = nil
        return img
    }

    /// The whole file on this phone. Calls `progress` with 0...1.
    func local(_ refIn: RemoteRef, progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws -> URL {
        var ref = refIn
        if ref.mtime == 0 || ref.size < 0 { ref = try await info(ref.path) }
        if ref.size > maxBytes { throw RelayErrorText("Die Datei ist größer als 100 MB.") }
        let dir = root.appendingPathComponent("\(Self.hash(ref.path))-\(Int(ref.mtime))", isDirectory: true)
        let dest = dir.appendingPathComponent(FileKinds.safeName(ref.name))
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        if let t = inflight[dest.path] { return try await t.value }
        let r = ref
        let task = Task { @MainActor () throws -> URL in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let tmp = dir.appendingPathComponent(".part")
            FileManager.default.createFile(atPath: tmp.path, contents: nil)
            let h = try FileHandle(forWritingTo: tmp)
            defer { try? h.close() }
            var offset = 0
            while true {
                let c = try await AppModel.shared.rpc("file_get", ["path": .string(r.path), "offset": .number(Double(offset)), "length": .number(524288)], timeout: 60)
                guard let data = Data(base64Encoded: c.str("data_b64")) else { throw RelayErrorText("Ungültige Antwort vom Gateway") }
                try h.write(contentsOf: data)
                offset += data.count
                let total = max(c["size"].int ?? r.size, 1)
                progress(min(1, Double(offset) / Double(total)))
                if c.flag("eof") || data.isEmpty { break }
                if offset > self.maxBytes { throw RelayErrorText("Die Datei ist größer als 100 MB.") }
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        }
        inflight[dest.path] = task
        defer { inflight[dest.path] = nil }
        return try await task.value
    }

    /// Frees the cache (used by the settings if wanted).
    func clear() { try? FileManager.default.removeItem(at: root); memory.removeAllObjects() }
}
