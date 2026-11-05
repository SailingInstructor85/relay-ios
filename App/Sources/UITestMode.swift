import Foundation

/// UI-Testmodus: nur aktiv mit dem Startargument `-relayUITest`. Setzt den App-Zustand zurück, übernimmt Host, Port,
/// Benutzer und den SSH-Seed (32 Byte, hex) aus der Startumgebung und schaltet die Face-ID-Sperre ab.
/// Umgebung: RELAY_UI_HOST, RELAY_UI_PORT, RELAY_UI_USER, RELAY_UI_SEED, RELAY_UI_PREFILL (1: Einstellungen vorbelegen).
enum UITestMode {
    static let active = ProcessInfo.processInfo.arguments.contains("-relayUITest")
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    static func hex(_ s: String) -> Data? {
        guard s.count % 2 == 0 else { return nil }
        var d = Data(); var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            d.append(b); i = j
        }
        return d
    }

    static var seed: Data? { active ? env["RELAY_UI_SEED"].flatMap(hex) : nil }

    /// Vor dem ersten Zugriff auf Einstellungen und Dateien aufrufen.
    static func prepare() {
        guard active else { return }
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        let fm = FileManager.default
        for dir in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory, .documentDirectory] {
            if let u = fm.urls(for: dir, in: .userDomainMask).first, let items = try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil) {
                for i in items { try? fm.removeItem(at: i) }
            }
        }
        let d = UserDefaults.standard
        d.set(false, forKey: "lockEnabled")
        if env["RELAY_UI_PREFILL"] == "1" {
            d.set(env["RELAY_UI_HOST"] ?? "127.0.0.1", forKey: "host")
            d.set(Int(env["RELAY_UI_PORT"] ?? "22") ?? 22, forKey: "port")
            d.set(env["RELAY_UI_USER"] ?? "", forKey: "user")
        }
    }
}
