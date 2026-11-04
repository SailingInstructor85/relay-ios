import Foundation
import Crypto
import NIOSSH

/// The phone's Ed25519 SSH identity. The app stores `rawSeed` in the Keychain.
public struct Identity: Sendable {
    public let privateKey: Curve25519.Signing.PrivateKey

    public init() { privateKey = Curve25519.Signing.PrivateKey() }
    public init(rawSeed: Data) throws { privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawSeed) }

    public var rawSeed: Data { privateKey.rawRepresentation }

    /// `ssh-ed25519 AAAA… <comment>`, for `notifyd setup key "<this>"`.
    public func openSSHPublicKey(comment: String = "relay-iphone") -> String {
        let raw = privateKey.publicKey.rawRepresentation
        var blob = Data()
        blob.appendSSHString(Data("ssh-ed25519".utf8))
        blob.appendSSHString(raw)
        return "ssh-ed25519 \(blob.base64EncodedString()) \(comment)"
    }
}

extension Data {
    mutating func appendSSHString(_ d: Data) {
        var len = UInt32(d.count).bigEndian
        Swift.withUnsafeBytes(of: &len) { append(contentsOf: $0) }
        append(d)
    }
}

public enum HostKeys {
    /// "ssh-ed25519 AAAA…" of a server key (what the app pins).
    public static func openSSH(_ key: NIOSSHPublicKey) -> String { String(openSSHPublicKey: key) }

    /// OpenSSH-style "SHA256:…" fingerprint of an "algo base64" key line, for display.
    public static func fingerprint(_ openSSH: String) -> String {
        let parts = openSSH.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return openSSH }
        let digest = SHA256.hash(data: blob)
        var b64 = Data(digest).base64EncodedString()
        while b64.hasSuffix("=") { b64.removeLast() }
        return "SHA256:" + b64
    }
}
