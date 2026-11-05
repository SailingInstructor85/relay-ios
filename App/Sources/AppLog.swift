import Foundation
import MetricKit
import RelayCore

/// The app's errors and crashes for the Desktop (rpc `app_log`, read with `notifyd phone log`). Entries go out at once
/// while connected and are not buffered otherwise; only crashes (found at the next start) wait in a file for the next
/// connection. At most 200 entries per call.
@MainActor
final class AppLog {
    static let shared = AppLog()
    private var sentRecently: [String: Date] = [:]
    private func entry(_ level: String, _ tag: String, _ message: String, stack: String = "") -> JSON {
        CrashFile.entry(level, tag, message, stack: stack, ts: Date().timeIntervalSince1970)
    }

    /// One message now, only when connected. The same text is sent at most once a minute.
    func log(_ level: String, _ tag: String, _ message: String, stack: String = "") {
        let model = AppModel.shared
        guard model.state == .connected else { return }
        let k = "\(tag)|\(message)"
        if let t = sentRecently[k], Date().timeIntervalSince(t) < 60 { return }
        sentRecently[k] = Date()
        if sentRecently.count > 100 { sentRecently = sentRecently.filter { Date().timeIntervalSince($0.value) < 60 } }
        let e = entry(level, tag, message, stack: stack)
        Task { _ = try? await model.rpc("app_log", ["entries": .array([e])], timeout: 10) }
    }

    /// After `hello_ok`: sends the saved crashes and removes the file once the Desktop has them.
    func flushSaved() {
        guard let u = CrashFile.url, let d = try? Data(contentsOf: u), let list = JSON.parse(d)?.array, !list.isEmpty else { return }
        Task {
            if (try? await AppModel.shared.rpc("app_log", ["entries": .array(Array(list.suffix(200)))], timeout: 15)) != nil {
                try? FileManager.default.removeItem(at: u)
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
