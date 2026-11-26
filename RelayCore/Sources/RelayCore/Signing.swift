import Foundation

// MARK: Signatur und Update (2026-11-26)
//
// Mit kostenloser Apple-ID gilt die Signatur der App sieben Tage. SideStore erneuert sie nur, wenn das iPhone in
// einem WLAN eingebucht ist (LocalDevVPN geht nicht über Mobilfunk). Die App zeigt deshalb, wann die eigene Signatur
// abläuft, warnt ab drei Tagen Rest und meldet, wenn in der SideStore-Quelle eine neuere Version liegt.

/// Liest das Ablaufdatum aus `embedded.mobileprovision`. Die Datei ist ein signierter Umschlag (CMS), in dem eine
/// XML-Plist im Klartext steht. Gesucht wird nur zwischen `<?xml` und `</plist>`, der Rest bleibt ungelesen.
public enum Provisioning {
    public static func expiration(in data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let xml = String(decoding: data[start.lowerBound..<end.upperBound], as: UTF8.self)
        guard let key = xml.range(of: "<key>ExpirationDate</key>"),
              let open = xml.range(of: "<date>", range: key.upperBound..<xml.endIndex),
              let close = xml.range(of: "</date>", range: open.upperBound..<xml.endIndex) else { return nil }
        // Zwischen Schlüssel und Wert darf nur Leerraum stehen, sonst gehört das Datum zu einem anderen Schlüssel.
        guard xml[key.upperBound..<open.lowerBound].allSatisfy({ $0.isWhitespace }) else { return nil }
        let text = xml[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return ISO8601DateFormatter().date(from: text)
    }
}

/// Stand der Signatur zu einem Zeitpunkt, mit den Texten für Einstellungen, Hinweis und Mitteilungen.
public struct SigningStatus: Equatable, Sendable {
    /// Ab so vielen Tagen Rest steht der Hinweis oben in der App.
    public static let warnDays = 3
    public static let wifiHint = "Zum Erneuern in SideStore brauchst du ein WLAN (irgendeines, nicht nur das Heimnetz) und LocalDevVPN. Über Mobilfunk geht es nicht."

    public let expiry: Date
    public let now: Date

    public init(expiry: Date, now: Date) { self.expiry = expiry; self.now = now }

    public var remaining: TimeInterval { expiry.timeIntervalSince(now) }
    public var expired: Bool { remaining <= 0 }
    public var warn: Bool { remaining <= Double(Self.warnDays) * 86400 }

    private func parts(_ tz: TimeZone) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.dateComponents([.weekday, .day, .month, .hour, .minute], from: expiry)
    }

    private static func two(_ n: Int?) -> String { let v = n ?? 0; return v < 10 ? "0\(v)" : "\(v)" }

    /// „Mi, 02.12.“
    public func dayText(timeZone: TimeZone = .current) -> String {
        let p = parts(timeZone)
        let names = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let wd = names[max(0, min(6, (p.weekday ?? 1) - 1))]
        return "\(wd), \(Self.two(p.day)).\(Self.two(p.month))."
    }

    /// „22:18 Uhr“
    public func timeText(timeZone: TimeZone = .current) -> String {
        let p = parts(timeZone)
        return "\(Self.two(p.hour)):\(Self.two(p.minute)) Uhr"
    }

    /// „6 Tage“, „1 Tag“, „5 Stunden“, „weniger als 1 Stunde“. Angefangene Tage zählen nicht mit.
    public var remainingText: String {
        let r = max(0, remaining)
        let days = Int(r / 86400)
        if days >= 2 { return "\(days) Tage" }
        if days == 1 { return "1 Tag" }
        let hours = Int(r / 3600)
        if hours >= 2 { return "\(hours) Stunden" }
        if hours == 1 { return "1 Stunde" }
        return "weniger als 1 Stunde"
    }

    /// Dieselbe Angabe nach „in“: „in 2 Tagen“, „in 1 Tag“, „in 5 Stunden“.
    public var remainingDative: String {
        let t = remainingText
        return t.hasSuffix(" Tage") ? t + "n" : t
    }

    /// Zeile für Einstellungen und „Mehr“: „Signatur gültig bis Mi, 02.12., noch 6 Tage“.
    public func line(timeZone: TimeZone = .current) -> String {
        if expired { return "Signatur abgelaufen seit \(dayText(timeZone: timeZone)), \(timeText(timeZone: timeZone))" }
        return "Signatur gültig bis \(dayText(timeZone: timeZone)), noch \(remainingText)"
    }

    /// Erster Satz des Hinweises oben in der App (ab `warnDays` Tagen Rest).
    public func bannerTitle(timeZone: TimeZone = .current) -> String {
        let when = "\(dayText(timeZone: timeZone)), \(timeText(timeZone: timeZone))"
        if expired { return "Die Signatur von Relay ist abgelaufen (\(when))." }
        return "Die Signatur von Relay läuft in \(remainingDative) ab (\(when))."
    }

    /// So steht das Ablaufdatum im Nutzungsprotokoll (Feld `detail`), damit der PC warnen kann.
    public var usageDetail: String { "signatur_bis=" + ISO8601DateFormatter().string(from: expiry) }
}

/// Lokale Mitteilungen 72, 48 und 24 Stunden vor Ablauf. Geplant wird nur, was noch in der Zukunft liegt.
public enum SigningReminders {
    public static let hours = [72, 48, 24]
    public static let title = "Relay läuft bald ab"

    public struct Item: Equatable, Sendable {
        public let id: String
        public let fire: Date
        public let body: String
    }

    public static func id(_ hours: Int) -> String { "sign-\(hours)" }
    public static var ids: [String] { hours.map(id) }

    public static func plan(expiry: Date, now: Date, timeZone: TimeZone = .current) -> [Item] {
        hours.compactMap { h in
            let fire = expiry.addingTimeInterval(-Double(h) * 3600)
            guard fire > now else { return nil }
            let st = SigningStatus(expiry: expiry, now: fire)
            return Item(id: id(h), fire: fire, body: st.bannerTitle(timeZone: timeZone) + " " + SigningStatus.wifiHint)
        }
    }
}

/// Vergleich mit der SideStore-Quelle (`source.json` des neuesten Release).
public enum AppUpdate {
    public static let sourceURL = "https://github.com/SailingInstructor85/relay-ios/releases/latest/download/source.json"
    /// SideStore registriert das Schema `sidestore` (Info.plist, Zweig develop, gelesen am 26.11.2026).
    public static let storeURL = "sidestore://"
    public static let storeLabel = "SideStore öffnen"
    public static let hint = "Aktualisieren geht nur im WLAN mit LocalDevVPN."
    public static let storeFailed = "SideStore ließ sich von hier nicht öffnen. Öffne es bitte von Hand."
    /// Höchstens so oft wird die Quelle geladen.
    public static let checkEvery: TimeInterval = 6 * 3600

    private static func numbers(_ v: String) -> [Int] {
        var s = v.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// Zahlenweise, nicht als Text: 0.4.10 ist neuer als 0.4.9.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = numbers(a), y = numbers(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// `apps[0].versions[0].version` der Quelle.
    public static func latestVersion(in source: JSON) -> String? {
        guard let v = source["apps"][0]["versions"][0]["version"].string?.trimmingCharacters(in: .whitespaces),
              !v.isEmpty, numbers(v).contains(where: { $0 > 0 }) else { return nil }
        return v
    }

    /// Die Version aus der Quelle, wenn sie neuer ist als die eigene, sonst nil.
    public static func available(latest: String?, own: String) -> String? {
        guard let latest, isNewer(latest, than: own) else { return nil }
        return latest
    }

    public static func due(last: Double?, now: Double) -> Bool {
        guard let last else { return true }
        return now - last >= checkEvery || now < last
    }

    public static func title(_ version: String) -> String { "Update \(version) verfügbar" }
}
