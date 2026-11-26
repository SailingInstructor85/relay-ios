import SwiftUI

/// UI-Testmodus: nur aktiv mit dem Startargument `-relayUITest`. Setzt den App-Zustand zurück, übernimmt Host, Port,
/// Benutzer und den SSH-Seed (32 Byte, hex) aus der Startumgebung und schaltet die Face-ID-Sperre ab.
/// Umgebung: RELAY_UI_HOST, RELAY_UI_PORT, RELAY_UI_USER, RELAY_UI_SEED, RELAY_UI_PREFILL (1: Einstellungen vorbelegen),
/// RELAY_UI_SHARE (1: eine geteilte Testdatei liegt an, das Teilen-Blatt öffnet sich),
/// RELAY_UI_SCHEME (dark oder light: erzwingt das Farbschema für Bilder, sonst gilt das des Simulators),
/// RELAY_UI_SIGN_DAYS und RELAY_UI_UPDATE (künstliches Ablaufdatum der Signatur, künstliche Version in der Quelle),
/// RELAY_UI_KEEP (1: Einstellungen und Dateien des vorigen Starts bleiben, für Tests über einen Neustart der App hinweg).
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

    /// RELAY_UI_SCHEME=dark|light: festes Farbschema für die Bilder der UI-Tests. Außerhalb des Testmodus immer nil,
    /// die App folgt dann wie bisher dem System.
    static var colorScheme: ColorScheme? {
        guard active else { return nil }
        switch env["RELAY_UI_SCHEME"] {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    /// RELAY_UI_SIGN_DAYS (Zahl, auch 2.5): künstliches Ablaufdatum der Signatur, so viele Tage ab jetzt.
    /// Ohne die Angabe verhält sich die App wie im Simulator üblich: kein Profil, keine Anzeige.
    static var signDays: Double? { active ? env["RELAY_UI_SIGN_DAYS"].flatMap { Double($0) } : nil }

    /// RELAY_UI_UPDATE (Version wie 9.9.9): so, als läge diese Version in der SideStore-Quelle. Im Testmodus lädt die
    /// App die Quelle nie aus dem Netz.
    static var updateVersion: String? { active ? env["RELAY_UI_UPDATE"] : nil }

    /// RELAY_UI_SHARE=1: a small text file as if another app had shared it ("In Relay öffnen"), so the share sheet opens.
    static func shareFile() -> URL? {
        guard active, env["RELAY_UI_SHARE"] == "1" else { return nil }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("testbrief.txt")
        do { try Data("Testbrief vom 21.11.2026".utf8).write(to: u) } catch { return nil }
        return u
    }

    /// Vor dem ersten Zugriff auf Einstellungen und Dateien aufrufen.
    static func prepare() {
        guard active, env["RELAY_UI_KEEP"] != "1" else { return }
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

/// Unsichtbare Marke für die UI-Tests: Der Startbildschirm ist da und hat Daten vom Gateway. Die Tests warten beim
/// Start auf die Kennung `homeReady` statt auf einen sichtbaren Text, damit Umbenennungen und der Umbau auf Tabs sie
/// nicht brechen. Gesetzt wird sie am Tab-Rahmen (`RootTabs`), unabhängig vom gewählten Tab. Außerhalb des Testmodus
/// entsteht kein Element (auch nicht für VoiceOver). Bewusst ohne Beschriftung: Die Tests suchen Texte per „enthält“,
/// ein Wort wie „bereit“ würde mit dem Abschnitt „Bereit“ verwechselt.
struct HomeReadyMarker: View {
    static let identifier = "homeReady"
    let ready: Bool

    var body: some View {
        if UITestMode.active && ready {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(Self.identifier)
                .allowsHitTesting(false)
        }
    }
}
