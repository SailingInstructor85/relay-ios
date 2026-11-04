import Foundation
import RelayCore

// Linux smoke test of RelayCore against a real gateway:
//   relay-smoke <host> <port> <user> <seedfile> [rpc-method [json-params]]
// The seed file holds the 32-byte raw Ed25519 seed (created when missing; its public key is printed).
let args = CommandLine.arguments
guard args.count >= 5 else {
    print("usage: relay-smoke <host> <port> <user> <seedfile> [method [json]]"); exit(2)
}
let seedURL = URL(fileURLWithPath: args[4])
let identity: Identity
if let d = try? Data(contentsOf: seedURL), d.count == 32 { identity = try Identity(rawSeed: d) }
else { identity = Identity(); try identity.rawSeed.write(to: seedURL) }
print("pubkey:", identity.openSSHPublicKey())

let link = GatewayLink(config: ServerConfig(host: args[1], port: Int(args[2]) ?? 22, user: args[3]), identity: identity,
                       pinnedHostKey: nil,
                       onHostKey: { print("hostkey (TOFU):", HostKeys.fingerprint($0)) },
                       onEvent: { ev in
                           let t = ev.str("type")
                           if t == "hello_ok" {
                               let ss = ev["sessions"].array.compactMap(Session.from)
                               print("hello_ok seq=\(ev.num("seq")) sessions=\(ss.count) accounts=\(ev["accounts"].array.count)")
                               for s in ss { print("  -", s.key, s.state, s.name) }
                           } else { print("event:", t, ev.serialized().prefix(200)) }
                       })

let runner = Task {
    do { try await link.run(hello: Hello.make(sinceSeq: 0, pinned: [], appVersion: "smoke")) }
    catch { print("link ended:", error.localizedDescription) }
}
// wait for the link
for _ in 0..<100 where !link.isOpen { try await Task.sleep(nanoseconds: 100_000_000) }
try await Task.sleep(nanoseconds: 1_500_000_000)
let method = args.count > 5 ? args[5] : "ping"
let params = args.count > 6 ? (JSON.parse(args[6]) ?? [:]) : [:]
do {
    let r = try await link.rpc(method, params)
    print("rpc \(method):", r.serialized().prefix(3000))
} catch { print("rpc \(method) failed:", error.localizedDescription) }
link.close()
_ = await runner.result
