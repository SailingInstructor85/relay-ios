import Foundation
import MetricKit
import RelayCore

/// The app's errors and crashes for the Desktop (rpc `app_log`, read with `notifyd phone log`). Entries go out at once
/// while connected and are not buffered otherwise; crashes (found at the next start) and entries logged with
/// `keep` (Rückfälle auf die Apple-Stimme) wait in a file for the next connection. At most 200 entries per call.
@MainActor
final class AppLog {
    static let shared = AppLog()
    private var sentRecently: [String: Date] = [:]
    private func entry(_ level: String, _ tag: String, _ message: String, stack: String = "") -> JSON {
        CrashFile.entry(level, tag, message, stack: stack, ts: Date().timeIntervalSince1970)
    }

    /// One message now, only when connected. The same text is sent at most once a minute. `keep`: without a
    /// connection (or when sending fails) the entry waits in a file and goes out after the next `hello_ok`.
    func log(_ level: String, _ tag: String, _ message: String, stack: String = "", keep: Bool = false) {
        let model = AppModel.shared
        let connected = model.state == .connected
        guard connected || keep else { return }
        let k = "\(tag)|\(message)"
        if let t = sentRecently[k], Date().timeIntervalSince(t) < 60 { return }
        sentRecently[k] = Date()
        if sentRecently.count > 100 { sentRecently = sentRecently.filter { Date().timeIntervalSince($0.value) < 60 } }
        let e = entry(level, tag, message, stack: stack)
        guard connected else { KeptFile.save(e); return }
        Task {
            let sent = (try? await model.rpc("app_log", ["entries": .array([e])], timeout: 10)) != nil
            if !sent && keep { KeptFile.save(e) }
        }
    }

    /// After `hello_ok`: sends the saved crashes and kept entries and removes each file once the Desktop has them.
    func flushSaved() {
        for u in [CrashFile.url, KeptFile.url].compactMap({ $0 }) {
            guard let d = try? Data(contentsOf: u), let list = JSON.parse(d)?.array, !list.isEmpty else { continue }
            Task {
                if (try? await AppModel.shared.rpc("app_log", ["entries": .array(Array(list.suffix(200)))], timeout: 15)) != nil {
                    // nur löschen, wenn inzwischen nichts dazugekommen ist; sonst geht der Rest beim nächsten Mal mit
                    let now = (try? Data(contentsOf: u)).flatMap { JSON.parse($0) }?.array ?? []
                    if now.count <= list.count {
                        try? FileManager.default.removeItem(at: u)
                    } else if let rest = try? JSONEncoder().encode(JSON.array(Array(now.suffix(now.count - list.count)))) {
                        try? rest.write(to: u, options: .atomic)
                    }
                }
            }
        }
    }

    /// Call once at start: Objective-C exceptions are saved by the handler, native crashes arrive next start via MetricKit.
    func install() {
        NSSetUncaughtExceptionHandler { ex in
            let stack = ex.callStackSymbols.joined(separator: "\n")
            let msg = "\(ex.name.rawValue): \(ex.reason ?? "")"
            CrashFile.save(tag: "exception", message: msg, stack: stack, ts: Date().timeIntervalSince1970)
        }
        MXMetricManager.shared.add(MetricsCatcher.shared)
    }
}

/// Crash reports of the previous run (MetricKit delivers them at the next start).
final class MetricsCatcher: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricsCatcher()

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var found: [(String, String, Double)] = []
        for p in payloads {
            for c in p.crashDiagnostics ?? [] {
                let sig = c.signal.map { "signal \($0)" } ?? "crash"
                let what = c.exceptionType.map { "exception type \($0)" } ?? ""
                let stack = String(data: c.callStackTree.jsonRepresentation(), encoding: .utf8) ?? ""
                found.append(("\(sig) \(what) \(c.terminationReason ?? "")", stack, p.timeStampEnd.timeIntervalSince1970))
            }
        }
        guard !found.isEmpty else { return }
        Task { @MainActor in
            for (m, st, ts) in found { CrashFile.save(tag: "crash", message: m, stack: st, ts: ts) }
            AppLog.shared.flushSaved()
        }
    }
    func didReceive(_ payloads: [MXMetricPayload]) {}
}

/// The crash file, usable from any thread (an exception handler runs wherever the crash happens).
enum CrashFile {
    static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("crash-log.json")
    }

    static func entry(_ level: String, _ tag: String, _ message: String, stack: String, ts: Double) -> JSON {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return ["ts": .number(ts), "level": .string(level), "tag": .string(tag), "message": .string(String(message.prefix(2000))),
                "stack": .string(String(stack.prefix(8000))), "app_version": .string("ios \(v) (\(b))")]
    }

    static func save(tag: String, message: String, stack: String, ts: Double) {
        guard let u = url else { return }
        var list = (try? Data(contentsOf: u)).flatMap { JSON.parse($0) }?.array ?? []
        list.append(entry("crash", tag, message, stack: stack, ts: ts))
        if let d = try? JSONEncoder().encode(JSON.array(Array(list.suffix(20)))) { try? d.write(to: u, options: .atomic) }
    }
}

/// Protokolleinträge, die auf die nächste Verbindung warten (`AppLog.log(..., keep: true)`). Nur vom Hauptthread.
@MainActor
enum KeptFile {
    static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("kept-log.json")
    }

    static func save(_ entry: JSON) {
        guard let u = url else { return }
        let list = (try? Data(contentsOf: u)).flatMap { JSON.parse($0) }?.array ?? []
        if let d = try? JSONEncoder().encode(JSON.array(KeptLog.appended(list, entry))) { try? d.write(to: u, options: .atomic) }
    }
}
