import Foundation
import Network

/// A quick TCP probe of the PC's addresses before the SSH connect: with two addresses (LAN and Tailscale) the one that
/// answers first is used. No route (VPN off) fails at once instead of waiting for the SSH timeout.
enum Reach {
    /// The first of `hosts` that accepts a TCP connection on `port` within `timeout` seconds; nil when none does.
    static func first(of hosts: [String], port: Int, timeout: Double) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            for h in hosts { group.addTask { await probe(h, port: port, timeout: timeout) ? h : nil } }
            var hit: String?
            for await r in group { if let r { hit = r; group.cancelAll(); break } }
            return hit
        }
    }

    static func probe(_ host: String, port: Int, timeout: Double) async -> Bool {
        guard let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        let once = Once()
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            conn.stateUpdateHandler = { st in
                switch st {
                case .ready: if once.take() { c.resume(returning: true) }; conn.cancel()
                case .waiting, .failed: if once.take() { c.resume(returning: false) }; conn.cancel()
                case .cancelled: if once.take() { c.resume(returning: false) }
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.take() { c.resume(returning: false) }
                conn.cancel()
            }
        }
    }
}

/// Resumes a continuation exactly once from whichever callback comes first.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}
