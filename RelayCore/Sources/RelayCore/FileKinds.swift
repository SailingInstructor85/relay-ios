import Foundation

/// How the viewer shows a file, which icon a chip gets, its mime type (port of Android FileKinds).
public enum FileKinds {
    public enum Mode: Sendable { case image, pdf, text, markdown, other }
    public enum Icon: Sendable { case image, pdf, text, code, audio, video, file }

    private static let imageExt: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "avif"]
    private static let codeExt: Set<String> = ["kt", "kts", "java", "py", "js", "mjs", "cjs", "ts", "tsx", "jsx", "c", "h", "cc", "cpp", "hpp", "cxx", "rs", "go", "rb", "php",
        "swift", "dart", "scala", "lua", "pl", "r", "sh", "bash", "zsh", "fish", "ps1", "sql", "gradle", "html", "htm", "css", "scss", "xml", "vue", "svelte",
        "json", "jsonl", "yaml", "yml", "toml", "ini", "cfg", "conf", "properties", "tex", "bib", "cmake", "mk", "diff", "patch", "svg", "proto", "nix"]
    private static let textExt: Set<String> = codeExt.union(["txt", "log", "csv", "tsv", "md", "markdown", "rst", "org", "srt", "vtt", "lock", "env", "out", "err"])
    private static let textNames: Set<String> = ["makefile", "dockerfile", "readme", "license", "changelog", "notice", "authors", "gemfile", "procfile", "justfile",
        ".gitignore", ".gitattributes", ".editorconfig", ".bashrc", ".zshrc", ".profile"]
    private static let audioExt: Set<String> = ["mp3", "wav", "ogg", "oga", "opus", "m4a", "aac", "flac", "amr", "mid", "midi"]
    private static let videoExt: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv", "avi", "3gp"]
    private static let mimes: [String: String] = [
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "webp": "image/webp", "heic": "image/heic",
        "heif": "image/heif", "bmp": "image/bmp", "avif": "image/avif", "svg": "image/svg+xml", "pdf": "application/pdf",
        "txt": "text/plain", "log": "text/plain", "md": "text/markdown", "markdown": "text/markdown", "csv": "text/csv", "tsv": "text/tab-separated-values",
        "json": "application/json", "html": "text/html", "htm": "text/html", "xml": "text/xml", "css": "text/css", "js": "text/javascript",
        "zip": "application/zip", "gz": "application/gzip", "tar": "application/x-tar",
        "doc": "application/msword", "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls": "application/vnd.ms-excel", "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt": "application/vnd.ms-powerpoint", "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "odt": "application/vnd.oasis.opendocument.text", "ods": "application/vnd.oasis.opendocument.spreadsheet", "epub": "application/epub+zip",
        "mp3": "audio/mpeg", "wav": "audio/wav", "ogg": "audio/ogg", "opus": "audio/opus", "m4a": "audio/mp4", "aac": "audio/aac", "flac": "audio/flac",
        "mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime", "webm": "video/webm", "mkv": "video/x-matroska", "3gp": "video/3gpp",
    ]

    private static func lastPart(_ name: String) -> String { name.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? name }

    public static func ext(_ name: String) -> String {
        let n = lastPart(name)
        if n.hasPrefix("."), n.filter({ $0 == "." }).count == 1 { return "" }
        guard let i = n.lastIndex(of: ".") else { return "" }
        return String(n[n.index(after: i)...]).lowercased()
    }
    private static func base(_ name: String) -> String { lastPart(name).lowercased() }

    private static func texty(_ mime: String) -> Bool {
        mime.hasPrefix("text/") || ["application/json", "application/xml", "application/javascript", "application/x-sh", "application/x-yaml",
                                    "application/yaml", "application/toml", "application/sql", "application/x-ndjson"].contains(mime)
    }

    public static func isImage(_ name: String, mime: String = "", kind: String = "") -> Bool {
        ext(name) != "svg" && (kind == "image" || (mime.hasPrefix("image/") && mime != "image/svg+xml") || imageExt.contains(ext(name)))
    }

    public static func mode(_ name: String, mime: String = "", kind: String = "") -> Mode {
        let e = ext(name)
        if e == "md" || e == "markdown" { return .markdown }
        if e == "svg" { return .text }
        if isImage(name, mime: mime, kind: kind) { return .image }
        if kind == "pdf" || mime == "application/pdf" || e == "pdf" { return .pdf }
        if kind == "text" || texty(mime) || textExt.contains(e) || textNames.contains(base(name)) { return .text }
        return .other
    }

    public static func icon(_ name: String, mime: String = "", kind: String = "") -> Icon {
        let e = ext(name)
        if isImage(name, mime: mime, kind: kind) { return .image }
        if kind == "pdf" || mime == "application/pdf" || e == "pdf" { return .pdf }
        if codeExt.contains(e) { return .code }
        if kind == "text" || texty(mime) || textExt.contains(e) || textNames.contains(base(name)) { return .text }
        if kind == "audio" || mime.hasPrefix("audio/") || audioExt.contains(e) { return .audio }
        if kind == "video" || mime.hasPrefix("video/") || videoExt.contains(e) { return .video }
        return .file
    }

    /// SF Symbol name for a chip.
    public static func symbol(_ i: Icon) -> String {
        switch i {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .audio: return "waveform"
        case .video: return "film"
        case .file: return "doc"
        }
    }

    public static func mime(_ name: String, mime: String = "") -> String {
        if !mime.trimmingCharacters(in: .whitespaces).isEmpty, mime != "application/octet-stream" { return mime }
        let e = ext(name)
        return mimes[e] ?? (textExt.contains(e) || textNames.contains(base(name)) ? "text/plain" : "application/octet-stream")
    }

    /// The kind the gateway would send, from the name.
    public static func kindOf(_ name: String, mime: String = "") -> String {
        switch icon(name, mime: mime) {
        case .image: return "image"
        case .pdf: return "pdf"
        case .text, .code: return "text"
        case .audio: return "audio"
        case .video: return "video"
        case .file: return "other"
        }
    }

    /// A file name safe for the cache and for saving: no folders, no control characters, at most 120 characters.
    public static func safeName(_ name: String) -> String {
        var n = String(lastPart(name).split(separator: "\\", omittingEmptySubsequences: false).last ?? "")
        n = String(n.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 })
        for c in [":", "*", "?", "\"", "<", ">", "|"] { n = n.replacingOccurrences(of: c, with: "_") }
        n = n.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if n.isEmpty { return "file" }
        if n.count <= 120 { return n }
        let e = String(ext(n).prefix(10))
        return e.isEmpty ? String(n.prefix(120)) : String(n.prefix(119 - e.count)) + "." + e
    }

    /// "1.2 MB", "340 KB", "" for unknown sizes.
    public static func sizeLabel(_ size: Int) -> String {
        if size < 0 { return "" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return "\(Int((Double(size) / 1024).rounded())) KB" }
        let mb = Double(size) / 1048576
        return mb < 10 ? String(format: "%.1f MB", mb) : "\(Int(mb.rounded())) MB"
    }
}

/// A file tool's row in the chat: its file's name (tappable) first, then where it is.
public enum ToolPaths {
    /// `/home/u/a/b` -> `~/a/b`; paths outside a home folder stay.
    public static func short(_ path: String) -> String {
        LinkTargets.home(path).map { "~" + path.dropFirst($0.count) } ?? path
    }

    /// (name, rest): rest is the folder when the summary is just the path, else the summary as the gateway wrote it.
    public static func split(summary: String, path: String) -> (name: String, rest: String) {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let name = trimmed.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? trimmed
        let s = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == path || s == short(path) {
            let dir = path.contains("/") ? String(path[..<path.lastIndex(of: "/")!]) : ""
            return (name, short(dir))
        }
        return (name, s)
    }

    /// Tools that work on one file and carry its path.
    public static func isFileTool(_ name: String) -> Bool { ["Read", "Edit", "Write", "NotebookEdit", "MultiEdit"].contains(name) }
}

/// Zoom and pan of the image viewer.
public enum ZoomMath {
    public static let max: Double = 6
    public static let doubleTap: Double = 2.5
    public static func maxOffset(fitted: Double, view: Double, scale: Double) -> Double { Swift.max((fitted * scale - view) / 2, 0) }
    public static func clamp(_ v: Double, fitted: Double, view: Double, scale: Double) -> Double {
        let m = maxOffset(fitted: fitted, view: view, scale: scale)
        return Swift.min(Swift.max(v, -m), m)
    }
}
