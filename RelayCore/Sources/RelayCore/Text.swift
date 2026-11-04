import Foundation

public enum TermText {
    /// Removes ANSI escape sequences (CSI, OSC, charset selects) from a tmux capture.
    public static func stripANSI(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var it = s.unicodeScalars.makeIterator()
        while let c = it.next() {
            guard c == "\u{1B}" else { out.append(c); continue }
            guard let n = it.next() else { break }
            switch n {
            case "[": // CSI: params until a final byte 0x40-0x7E
                while let x = it.next() { if (0x40...0x7E).contains(x.value) { break } }
            case "]": // OSC: until BEL or ESC \
                while let x = it.next() {
                    if x == "\u{07}" { break }
                    if x == "\u{1B}" { _ = it.next(); break }
                }
            case "(", ")", "*", "+": _ = it.next()
            default: break
            }
        }
        return String(out)
    }

    /// "vor 5 Min." style relative time from unix seconds.
    public static func ago(_ ts: Double, now: Date = Date()) -> String {
        guard ts > 0 else { return "" }
        let d = now.timeIntervalSince1970 - ts
        if d < 60 { return "jetzt" }
        if d < 3600 { return "\(Int(d / 60)) Min." }
        if d < 86400 { return "\(Int(d / 3600)) Std." }
        return "\(Int(d / 86400)) T."
    }
}
