import Foundation

/// Zahlen als deutsche Wörter für die Sprachausgabe (2026-11-24). Die Hörproben mit Supertonic 3 und Piper lasen
/// „1081“ falsch; eine Stimme, die Ziffern nicht sicher liest, bekommt den Text deshalb mit ausgeschriebenen Zahlen.
/// Für die Apple-Stimme ist das nicht nötig (sie liest Zahlen, Daten und Uhrzeiten selbst richtig), dort bleibt der
/// Text, wie er ist. Reine Textregeln, nur für deutsche Sätze.
public enum SpokenNumbers {
    static let ones = ["null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf",
                       "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn"]
    static let tens = ["", "", "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig"]
    static let months = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober",
                         "November", "Dezember"]

    /// `alone`: die Zahl steht für sich („eins“), sonst vor einem Wort („ein Uhr“, „ein Euro“, „einhundert“).
    static func below100(_ n: Int, alone: Bool) -> String {
        if n < 20 { return n == 1 ? (alone ? "eins" : "ein") : ones[n] }
        let e = n % 10, t = n / 10
        return e == 0 ? tens[t] : (e == 1 ? "ein" : ones[e]) + "und" + tens[t]
    }

    static func below1000(_ n: Int, alone: Bool) -> String {
        let h = n / 100, r = n % 100
        return (h > 0 ? (h == 1 ? "ein" : ones[h]) + "hundert" : "") + (r > 0 ? below100(r, alone: alone) : "")
    }

    /// Grundzahl von 0 bis 999 999 999 999: 1081 → „eintausendeinundachtzig“, 2 000 000 → „zwei Millionen“.
    public static func cardinal(_ n: Int, alone: Bool = true) -> String {
        guard n > 0 else { return "null" }
        guard n < 1_000_000_000_000 else { return digits(String(n)) }
        var parts: [String] = []
        let mrd = n / 1_000_000_000, mio = n / 1_000_000 % 1000, t = n / 1000 % 1000, r = n % 1000
        if mrd > 0 { parts.append(mrd == 1 ? "eine Milliarde" : below1000(mrd, alone: true) + " Milliarden") }
        if mio > 0 { parts.append(mio == 1 ? "eine Million" : below1000(mio, alone: true) + " Millionen") }
        let low = (t > 0 ? below1000(t, alone: false) + "tausend" : "") + (r > 0 ? below1000(r, alone: alone) : "")
        if !low.isEmpty { parts.append(low) }
        return parts.joined(separator: " ")
    }

    /// Ziffer für Ziffer: „0830“ → „null acht drei null“.
    static func digits(_ s: String) -> String {
        s.compactMap { $0.wholeNumberValue }.map { ones[$0] }.joined(separator: " ")
    }

    /// Eine Ziffernfolge: mit führender Null oder mehr als neun Stellen (Kennungen, Laufnummern) Ziffer für Ziffer,
    /// sonst als Grundzahl.
    static func integer(_ s: String, alone: Bool = true) -> String {
        if (s.count > 1 && s.hasPrefix("0")) || s.count > 9 { return digits(s) }
        guard let n = Int(s) else { return s }
        return cardinal(n, alone: alone)
    }

    /// Ordnungszahl ohne Endung: 1 → „erst“, 3 → „dritt“, 24 → „vierundzwanzigst“.
    static func ordinalStem(_ n: Int) -> String {
        switch n {
        case 1: return "erst"
        case 3: return "dritt"
        case 7: return "siebt"
        case 8: return "acht"
        default: return n < 20 ? ones[n] + "t" : cardinal(n) + "st"
        }
    }

    /// Endung der Ordnungszahl nach dem Wort davor: „der erste“, „am ersten“, ohne Wort `fallback`.
    static func ending(after word: String?, fallback: String) -> String {
        guard let w = word?.lowercased(), !w.isEmpty else { return fallback }
        return ["der", "die", "das"].contains(w) ? "e" : "en"
    }

    /// Jahreszahl: 1100 bis 1999 als „neunzehnhundert…“, sonst wie eine Zahl.
    static func year(_ s: String) -> String {
        if s.count == 4, let y = Int(s), y >= 1100, y <= 1999 {
            return below100(y / 100, alone: false) + "hundert" + (y % 100 > 0 ? below100(y % 100, alone: true) : "")
        }
        return integer(s)
    }

    /// Alle Zahlen eines deutschen Textes als Wörter: Daten („am 24.11.2026“ → „am vierundzwanzigsten November
    /// zweitausendsechsundzwanzig“), Uhrzeiten („14:30 Uhr“ → „vierzehn Uhr dreißig“), Ordnungszahlen nach Artikel
    /// („der 1. Platz“), Versionen („0.4.4“ → „null Punkt vier Punkt vier“), Tausenderpunkte, Komma, Euro und Prozent.
    /// Ziffern, die an Buchstaben hängen („R1“, „M2“, „2da5687“), bleiben stehen.
    public static func german(_ text: String) -> String {
        var t = text

        // „Version 0.4.4“, „v0.4.5“
        t = sub(t, #"(?i)\bv(?=\d+\.\d)"#) { _, _ in "" }
        // Datum: Tag.Monat. mit oder ohne Jahr, davor vielleicht „am“, „der“, „bis“
        t = sub(t, #"(?i)(?:\b(der|die|das|am|vom|zum|dem|den|seit|ab|bis|beim)\s+)?(?<![\d.,\p{L}])(\d{1,2})\.(\d{1,2})\.(?:(\d{4}|\d{2})(?!\d))?(?!\d)"#) { m, ns in
            guard let d = Int(group(m, 2, ns) ?? ""), let mo = Int(group(m, 3, ns) ?? ""), d >= 1, d <= 31, mo >= 1, mo <= 12 else { return nil }
            let word = group(m, 1, ns)
            var out = (word.map { $0 + " " } ?? "") + ordinalStem(d) + ending(after: word, fallback: "er") + " " + months[mo - 1]
            if let y = group(m, 4, ns) { out += " " + year(y) }
            return out
        }
        // Uhrzeit, ein folgendes „Uhr“ wird nicht doppelt gesagt
        t = sub(t, #"(?<![\d.:,])(\d{1,2}):(\d{2})(?::\d{2})?(?![\d:])(?:\s*Uhr\b)?"#) { m, ns in
            guard let h = Int(group(m, 1, ns) ?? ""), let mi = Int(group(m, 2, ns) ?? ""), h <= 24, mi <= 59 else { return nil }
            return (h == 0 ? "null" : below100(h, alone: false)) + " Uhr" + (mi > 0 ? " " + below100(mi, alone: true) : "")
        }
        // Ordnungszahl nach Artikel oder Präposition: „am 3. Dezember“, „der 1. Platz“
        t = sub(t, #"(?i)\b(der|die|das|den|dem|des|am|im|zum|vom|beim)\s+(\d{1,3})\.(?=\s+\p{L})"#) { m, ns in
            guard let word = group(m, 1, ns), let n = Int(group(m, 2, ns) ?? ""), n > 0 else { return nil }
            return word + " " + ordinalStem(n) + ending(after: word, fallback: "en")
        }
        // Punkte zwischen Ziffern, die keine Tausenderpunkte sind: Versionen, Adressen, englische Dezimalzahlen
        t = sub(t, #"(?<![\d.,\p{L}])\d+(?:\.\d+)+(?![\d,\p{L}])"#) { m, ns in
            let parts = ns.substring(with: m.range).components(separatedBy: ".")
            if isThousands(parts) { return nil }
            return parts.map { integer($0) }.joined(separator: " Punkt ")
        }
        t = sub(t, #"(?<![\w.,])[-−](?=\d)"#) { _, _ in "minus " }
        // Zahl mit Tausenderpunkten, Komma, Euro oder Prozent
        t = sub(t, #"(?<![\d.,\p{L}])(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d+))?(?![\d\p{L}])(?:\s?(€|EUR\b|Euro\b|%))?"#) { m, ns in
            guard let raw = group(m, 1, ns) else { return nil }
            let plain = !raw.contains(".")
            let whole = raw.replacingOccurrences(of: ".", with: "")
            let frac = group(m, 2, ns), unit = group(m, 3, ns)
            let euro = unit != nil && unit != "%"
            if euro, let f = frac, f.count == 2, let cents = Int(f) {
                return integer(whole, alone: false) + " Euro" + (cents > 0 ? " " + cardinal(cents) : "")
            }
            // eine nackte vierstellige Zahl von 1100 bis 1999 wie eine Jahreszahl („neunzehnhundertfünfundachtzig“)
            var out = plain && frac == nil && unit == nil ? year(whole) : integer(whole, alone: !euro)
            if let f = frac { out += " Komma " + digits(f) }
            if let u = unit { out += u == "%" ? " Prozent" : " Euro" }
            return out
        }
        return t
    }

    /// „1.000.000“: erste Gruppe ein bis drei Ziffern ohne führende Null, danach nur Dreiergruppen.
    static func isThousands(_ parts: [String]) -> Bool {
        guard let first = parts.first, parts.count > 1, first.count <= 3, !first.hasPrefix("0") else { return false }
        return parts.dropFirst().allSatisfy { $0.count == 3 }
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ ns: NSString) -> String? {
        guard i < m.numberOfRanges else { return nil }
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }

    /// Ersetzt jeden Treffer durch das Ergebnis von `f`; nil lässt ihn stehen.
    private static func sub(_ s: String, _ pattern: String, _ f: (NSTextCheckingResult, NSString) -> String?) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f(m, ns) ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
