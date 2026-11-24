import Foundation

/// Der Gesprächskontext von Jarvis am PC (2026-11-24). Das Gateway führt je Tag ein Gespräch: Der Tag beginnt um
/// 4 Uhr (`DAY_STARTS_H` in `router.py`), und wird der Verlauf größer als 600 KB, beginnt es schon vorher ein neues.
/// Die App zeigt im Jarvis-Chat, wo ein neues Gespräch begonnen hat, damit klar ist, was Jarvis noch weiß. Kennt das
/// Gateway die RPCs `jarvis_context` und `jarvis_reset` (noch nicht gebaut), kommen der Füllstand und der Knopf
/// „Neues Gespräch beginnen“ dazu.
public enum JarvisContext {
    /// Stunde, zu der am PC ein neuer Jarvis-Tag beginnt (ein Gespräch nach Mitternacht gehört zum Abend davor).
    public static let dayStartsHour = 4

    public static let breakLabel = "Neues Gespräch. Jarvis kennt das Frühere nicht mehr."
    public static let nextBreakLabel = "Die nächste Frage beginnt ein neues Gespräch."
    public static let resetLabel = "Neues Gespräch beginnen"
    public static let resetDone = "Jarvis beginnt mit der nächsten Frage ein neues Gespräch."

    /// Der Jarvis-Tag eines Zeitpunkts als „JJJJ-MM-TT“.
    public static func day(_ ts: Double, startsHour: Int = dayStartsHour, calendar: Calendar = .current) -> String {
        let d = Date(timeIntervalSince1970: ts - Double(startsHour) * 3600)
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Zwischen `earlier` und `later` hat ein neues Gespräch begonnen: Tageswechsel oder ein Zurücksetzen per Knopf.
    public static func separated(_ earlier: Double, _ later: Double, resets: [Double], startsHour: Int = dayStartsHour,
                                 calendar: Calendar = .current) -> Bool {
        if day(earlier, startsHour: startsHour, calendar: calendar) != day(later, startsHour: startsHour, calendar: calendar) { return true }
        return resets.contains { $0 > earlier && $0 <= later }
    }

    /// Die Stellen im Verlauf (Index des Zugs), vor denen ein neues Gespräch beginnt. `times`: Zeit jedes Zugs, älteste
    /// zuerst.
    public static func breaks(times: [Double], resets: [Double], startsHour: Int = dayStartsHour,
                              calendar: Calendar = .current) -> Set<Int> {
        var out: Set<Int> = []
        guard times.count > 1 else { return out }
        for i in 1..<times.count where separated(times[i - 1], times[i], resets: resets, startsHour: startsHour, calendar: calendar) {
            out.insert(i)
        }
        return out
    }

    /// Nach dem letzten Zug steht ein neues Gespräch an (neuer Tag oder gerade zurückgesetzt): der Hinweis am Ende.
    public static func breakPending(last: Double?, now: Double, resets: [Double], startsHour: Int = dayStartsHour,
                                    calendar: Calendar = .current) -> Bool {
        guard let last else { return false }
        return separated(last, now, resets: resets, startsHour: startsHour, calendar: calendar)
    }

    /// Die gemerkten Zeitpunkte des Knopfs, mit dem neuen; nur die letzten 50 bleiben.
    public static func adding(_ now: Double, to resets: [Double]) -> [Double] { Array((resets + [now]).suffix(50)) }

    /// Antwort des RPC `jarvis_context`: wie voll das laufende Gespräch am PC ist.
    public struct Status: Equatable, Sendable {
        public let bytes: Double
        public let maxBytes: Double
        public init(bytes: Double, maxBytes: Double) { self.bytes = bytes; self.maxBytes = maxBytes }

        /// Füllstand in Prozent, 0 bis 100.
        public var percent: Int { Int((min(max(bytes / maxBytes, 0), 1) * 100).rounded()) }
    }

    /// nil, wenn die Antwort keine brauchbaren Zahlen enthält (dann gibt es weder Füllstand noch Knopf).
    public static func status(_ r: JSON) -> Status? {
        let maxBytes = r.num("max_bytes")
        guard maxBytes > 0 else { return nil }
        return Status(bytes: max(r.num("bytes"), 0), maxBytes: maxBytes)
    }

    public static func fillLabel(_ s: Status) -> String { "Gespräch am PC zu \(s.percent) % gefüllt" }
}
