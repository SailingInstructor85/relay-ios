import Foundation

/// fzf-like matching for search fields: every space-separated term must occur as a subsequence; matches at word starts,
/// in a row and in the last path component score higher. Smart case: a term with an upper-case letter is case-sensitive.
/// Port of the Android app's Fuzzy.kt.
public enum Fuzzy {
    private static func boundary(_ c: Character) -> Bool { c == "/" || c == "_" || c == "-" || c == "." || c == " " }

    public static func terms(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Sum of the term scores, nil if a term does not match. An empty query scores 0.
    public static func score(_ query: String, _ text: String) -> Int? {
        var total = 0
        for t in terms(query) {
            guard let s = termScore(t, text) else { return nil }
            total += s
        }
        return total
    }

    public static func termScore(_ term: String, _ text: String) -> Int? {
        let chars = Array(text)
        guard let (pos, _) = span(Array(term), chars) else { return nil }
        let base = (chars.lastIndex(of: "/") ?? -1) + 1
        var s = 0
        var prev = -2
        for j in pos {
            s += 16
            if j == 0 || boundary(chars[j - 1]) || (chars[j].isUppercase && chars[j - 1].isLowercase) { s += 10 }
            if j == prev + 1 { s += 6 }
            if j >= base { s += 4 }
            prev = j
        }
        return s - ((pos.last ?? 0) - (pos.first ?? 0) + 1 - pos.count)
    }

    /// Character positions (indices into `Array(text)`) to highlight for `query` (empty if it does not match).
    public static func positions(_ query: String, _ text: String) -> Set<Int> {
        let chars = Array(text)
        var out = Set<Int>()
        for t in terms(query) {
            guard let (pos, _) = span(Array(t), chars) else { return [] }
            out.formUnion(pos)
        }
        return out
    }

    private static func span(_ term: [Character], _ text: [Character]) -> ([Int], Int)? {
        if term.isEmpty { return nil }
        let sensitive = term.contains { $0.isUppercase }
        func eq(_ a: Character, _ b: Character) -> Bool { sensitive ? a == b : a.lowercased() == b.lowercased() }
        var i = 0
        var end = -1
        for j in text.indices where eq(text[j], term[i]) {
            i += 1
            if i == term.count { end = j; break }
        }
        if end < 0 { return nil }
        i = term.count - 1
        var start = end
        var j = end
        while j >= 0 {
            if eq(text[j], term[i]) {
                i -= 1
                if i < 0 { start = j; break }
            }
            j -= 1
        }
        var pos: [Int] = []
        i = 0
        for j in start...end where i < term.count && eq(text[j], term[i]) { pos.append(j); i += 1 }
        return (pos, end)
    }
}
