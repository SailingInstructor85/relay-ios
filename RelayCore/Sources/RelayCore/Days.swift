import Foundation

/// Kalendertage als Text `JJJJ-MM-TT`, so wie das Gateway sie für Termine liefert (lokale Zeit des PCs, ohne Zeitzone).
/// Rechnen und Beschriften für Posteingang (Gruppen nach Tag) und Kalender (Tage einer Woche).
public enum DayText {
    static let weekdays = ["So.", "Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa."]
    static let months = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober",
                         "November", "Dezember"]

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    private static let utc = TimeZone(identifier: "UTC") ?? .current

    /// Der Tag eines Zeitpunkts in der Zeitzone, „2026-11-22“.
    public static func key(_ date: Date, timeZone: TimeZone = .current) -> String {
        let c = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// Der Tag zu Unix-Sekunden.
    public static func key(ts: Double, timeZone: TimeZone = .current) -> String {
        key(Date(timeIntervalSince1970: ts), timeZone: timeZone)
    }

    /// Uhrzeit „09:05“ zu Unix-Sekunden.
    public static func clock(ts: Double, timeZone: TimeZone = .current) -> String {
        let c = calendar(timeZone).dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: ts))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Jahr, Monat, Tag aus „2026-11-22“ (auch aus „2026-11-22 09:30“); nil bei allem anderen.
    public static func parts(_ key: String) -> (year: Int, month: Int, day: Int)? {
        let p = key.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3, p[0].count == 4, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return (y, m, d)
    }

    private static func date(_ key: String) -> Date? {
        guard let p = parts(key) else { return nil }
        return calendar(utc).date(from: DateComponents(year: p.year, month: p.month, day: p.day, hour: 12))
    }

    /// Der Tag `days` Tage später (oder früher). Ein unlesbarer Tag bleibt, wie er ist.
    public static func add(_ key: String, _ days: Int) -> String {
        guard let d = date(key), let n = calendar(utc).date(byAdding: .day, value: days, to: d) else { return key }
        return self.key(n, timeZone: utc)
    }

    /// „Mo.“ zu einem Tag, leer bei unlesbarem Tag.
    public static func weekday(_ key: String) -> String {
        guard let d = date(key) else { return "" }
        return weekdays[(calendar(utc).component(.weekday, from: d) + 6) % 7]
    }

    /// Tag im Monat, „22“.
    public static func dayNumber(_ key: String) -> String { parts(key).map { String($0.day) } ?? "" }

    /// „Heute“, „Gestern“, „Morgen“, sonst „Mo., 23. November“; in einem anderen Jahr als heute mit Jahreszahl.
    public static func label(_ key: String, today: String) -> String {
        if key == today { return "Heute" }
        if key == add(today, -1) { return "Gestern" }
        if key == add(today, 1) { return "Morgen" }
        return long(key, today: today)
    }

    /// „Mo., 23. November“, in einem anderen Jahr als heute „Mo., 23. November 2025“.
    public static func long(_ key: String, today: String) -> String {
        guard let p = parts(key) else { return key }
        let year = parts(today)?.year == p.year ? "" : " \(p.year)"
        return "\(weekday(key)), \(p.day). \(months[p.month - 1])\(year)"
    }
}
