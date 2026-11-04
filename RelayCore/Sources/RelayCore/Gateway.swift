import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH

public struct ServerConfig: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var user: String
    public init(host: String, port: Int = 22, user: String) { self.host = host; self.port = port; self.user = user }
    public var isComplete: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty && !user.trimmingCharacters(in: .whitespaces).isEmpty }
}

public struct RelayError: Error, LocalizedError, Sendable {
    public let message: String
    /// The gateway answered and refused (vs. the link failed or timed out).
    public let remote: Bool
    public init(_ message: String, remote: Bool = false) { self.message = message; self.remote = remote }
    public var errorDescription: String? { message }
}

/// The host key the server showed did not match the pinned one.
public struct HostKeyMismatch: Error, LocalizedError, Sendable {
    public let presented: String
    public var errorDescription: String? { "Host-Schlüssel hat sich geändert (\(HostKeys.fingerprint(presented))). Verbindung abgelehnt." }
}

/// TOFU host-key check: no pin -> accept and report the key; a pin -> must match.
final class PinValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let pinned: String?
    let onFirstUse: @Sendable (String) -> Void
    private(set) var presented: String?
    init(pinned: String?, onFirstUse: @escaping @Sendable (String) -> Void) { self.pinned = pinned; self.onFirstUse = onFirstUse }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let line = HostKeys.openSSH(hostKey)
        presented = line
        let norm = { (s: String) in s.split(separator: " ").prefix(2).joined(separator: " ") }
        if let p = pinned, !p.isEmpty {
            if norm(p) == norm(line) { validationCompletePromise.succeed(()) }
            else { validationCompletePromise.fail(HostKeyMismatch(presented: line)) }
        } else {
            onFirstUse(line)
            validationCompletePromise.succeed(())
        }
    }
}

/// One SSH connection to the Desktop carrying the `serve` control channel (JSON lines both ways).
/// `run` connects, sends `hello`, delivers every incoming line (except rpc replies) to `onEvent` and returns or throws
/// when the link ends. RPCs can be called from any task while it runs.
public final class GatewayLink: @unchecked Sendable {
    public let config: ServerConfig
    private let identity: Identity
    private let pinnedHostKey: String?
    private let onHostKey: @Sendable (String) -> Void
    private let onEvent: @Sendable (JSON) -> Void

    private let lock = NSLock()
    private var writer: TTYStdinWriter?
    private var client: SSHClient?
    private var pending: [String: CheckedContinuation<JSON, Error>] = [:]
    private var progress: [String: @Sendable (String) -> Void] = [:]
    private var closed = false
    public private(set) var lastHeard = Date.distantPast

    public init(config: ServerConfig, identity: Identity, pinnedHostKey: String?,
                onHostKey: @escaping @Sendable (String) -> Void, onEvent: @escaping @Sendable (JSON) -> Void) {
        self.config = config; self.identity = identity; self.pinnedHostKey = pinnedHostKey
        self.onHostKey = onHostKey; self.onEvent = onEvent
    }

    public var isOpen: Bool { lock.withLock { writer != nil && !closed } }

    public func run(hello: JSON) async throws {
        let validator = PinValidator(pinned: pinnedHostKey, onFirstUse: onHostKey)
        let client: SSHClient
        do {
            client = try await SSHClient.connect(
                host: config.host, port: config.port,
                authenticationMethod: .ed25519(username: config.user, privateKey: identity.privateKey),
                hostKeyValidator: .custom(validator), reconnect: .never, connectTimeout: .seconds(12))
        } catch {
            if let m = error as? HostKeyMismatch { throw m }
            if let p = validator.presented, let pin = pinnedHostKey, !pin.isEmpty,
               p.split(separator: " ").prefix(2) != pin.split(separator: " ").prefix(2) { throw HostKeyMismatch(presented: p) }
            throw RelayError(Self.describe(error))
        }
        lock.withLock { self.client = client }
        defer { Task { try? await client.close() } }

        var errText = ""
        do {
            try await client.withExec("serve") { inbound, outbound in
                self.lock.withLock { self.writer = outbound }
                try await self.write(hello)
                var buf: [UInt8] = []
                for try await chunk in inbound {
                    switch chunk {
                    case .stdout(let bb):
                        buf.append(contentsOf: bb.readableBytesView)
                        while let nl = buf.firstIndex(of: 0x0A) {
                            let line = Array(buf[..<nl])
                            buf.removeSubrange(...nl)
                            self.handleLine(line)
                        }
                    case .stderr(let bb):
                        if errText.count < 1000 { errText += String(buffer: bb) }
                    }
                }
            }
        } catch {
            finish(RelayError(errText.isEmpty ? Self.describe(error) : errText.trimmingCharacters(in: .whitespacesAndNewlines)))
            throw RelayError(errText.isEmpty ? Self.describe(error) : String(errText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)))
        }
        let msg = errText.isEmpty ? "Gateway hat die Verbindung beendet" : String(errText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        finish(RelayError(msg))
        throw RelayError(msg)
    }

    static func describe(_ e: Error) -> String {
        if let r = e as? LocalizedError, let d = r.errorDescription { return d }
        let s = String(describing: e)
        if s.contains("allAuthenticationOptionsFailed") || s.contains("authentication") {
            return "Anmeldung abgelehnt: ist der Schlüssel auf dem Desktop eingetragen (notifyd setup key)?"
        }
        if s.contains("connectTimeout") || s.contains("timeout") { return "Zeitüberschreitung beim Verbinden" }
        if s.contains("connectionRefused") || s.contains("Connection refused") { return "Verbindung abgelehnt (läuft sshd?)" }
        return s
    }

    private func handleLine(_ bytes: [UInt8]) {
        lastHeard = Date()
        guard let o = JSON.parse(Data(bytes)) else { return }
        switch o.str("type") {
        case "rpc_result":
            let id = o.str("id")
            let c = lock.withLock { () -> CheckedContinuation<JSON, Error>? in progress[id] = nil; return pending.removeValue(forKey: id) }
            if o.flag("ok") { c?.resume(returning: o["result"]) }
            else { c?.resume(throwing: RelayError(o.str("error", "rpc failed"), remote: true)) }
        case "rpc_progress":
            let cb = lock.withLock { progress[o.str("id")] }
            cb?(o.str("delta"))
        default:
            onEvent(o)
        }
    }

    private func write(_ o: JSON) async throws {
        guard let w = lock.withLock({ writer }) else { throw RelayError("Nicht verbunden") }
        var bb = ByteBufferAllocator().buffer(capacity: 256)
        bb.writeString(o.serialized() + "\n")
        try await w.write(bb)
    }

    /// Calls an RPC (`{"type":"rpc","id","method","params"}`) and waits for its `rpc_result`.
    public func rpc(_ method: String, _ params: JSON = [:], timeout: Double = 30,
                    onProgress: (@Sendable (String) -> Void)? = nil) async throws -> JSON {
        guard isOpen else { throw RelayError("Nicht verbunden") }
        let id = String(UUID().uuidString.prefix(12))
        let timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            let c = self.lock.withLock { () -> CheckedContinuation<JSON, Error>? in self.progress[id] = nil; return self.pending.removeValue(forKey: id) }
            c?.resume(throwing: RelayError("\(method): Zeitüberschreitung"))
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<JSON, Error>) in
            let ok = lock.withLock { () -> Bool in
                if closed { return false }
                pending[id] = c
                if let p = onProgress { progress[id] = p }
                return true
            }
            guard ok else { c.resume(throwing: RelayError("Nicht verbunden")); return }
            Task {
                do { try await self.write(["type": "rpc", "id": .string(id), "method": .string(method), "params": params]) }
                catch {
                    let c2 = self.lock.withLock { self.pending.removeValue(forKey: id) }
                    c2?.resume(throwing: error)
                }
            }
        }
    }

    private func finish(_ err: Error) {
        let waiting = lock.withLock { () -> [CheckedContinuation<JSON, Error>] in
            closed = true; writer = nil
            let w = Array(pending.values); pending.removeAll(); progress.removeAll(); return w
        }
        waiting.forEach { $0.resume(throwing: err) }
    }

    /// Ends the link; `run` returns with an error shortly after.
    public func close() {
        let c = lock.withLock { client }
        finish(RelayError("Verbindung getrennt"))
        Task { try? await c?.close() }
    }
}

public enum Hello {
    public static func make(sinceSeq: Int, pinned: [String], appVersion: String) -> JSON {
        ["type": "hello", "since_seq": .number(Double(sinceSeq)), "client": "relay-ios", "version": 2,
         "app_version": .string(appVersion), "pinned": JSON(pinned.sorted())]
    }
}
