import Foundation

/// Text preparation for speech output and the conversation-mode stop words (port of Android SpeechText.kt).
public enum SpeechText {
    /// Fenced code out, markdown marks out, link text kept, whitespace collapsed.
    public static func strip(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"```[\s\S]*?```"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[#*`>_]+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first sentences of `text` that fit into `max` characters (spoken fallback when no summary is available).
    public static func brief(_ text: String, max: Int = 220) -> String {
        let t = strip(text)
        var out = ""
        for s in splitSentences(t) {
            if !out.isEmpty && out.count + s.count + 1 > max { break }
            if !out.isEmpty { out += " " }
            out += s
            if out.count >= max {
                var cut = String(out.prefix(max))
                if let sp = cut.lastIndex(of: " ") { cut = String(cut[..<sp]) }
                return cut + " …"
            }
        }
        return out
    }

    private static func splitSentences(_ t: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        let chars = Array(t)
        for (i, c) in chars.enumerated() {
            cur.append(c)
            if ".!?".contains(c), i + 1 < chars.count, chars[i + 1].isWhitespace {
                parts.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""
            }
        }
        let rest = cur.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { parts.append(rest) }
        return parts
    }

    public static let stopWords: Set<String> = ["stop", "stopp", "ende", "beenden", "danke", "dankeschön", "tschüss", "tschüs", "thanks", "bye"]

    public static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    /// "stop" or "danke" with at most two words around it; a long sentence that merely contains one ends nothing.
    public static func isStopPhrase(_ heard: String) -> Bool {
        let w = words(heard)
        return !w.isEmpty && w.count <= 3 && w.contains { stopWords.contains($0) }
    }
}

/// Collects streamed reply text and hands out whole sentences as soon as they are complete, so speaking starts while the
/// answer is still written. A sentence ends at a newline, or at . ! ? followed by whitespace once it has `minLen`
/// characters ("am 4. Oktober": no break after a digit).
public struct SentenceSplitter {
    private var buf: [Character] = []
    private let minLen: Int
    public init(minLen: Int = 12) { self.minLen = minLen }

    public mutating func add(_ delta: String) -> [String] {
        buf.append(contentsOf: delta)
        var out: [String] = []
        while let i = boundary() {
            let s = String(buf[..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
            buf.removeFirst(i)
            if !s.isEmpty { out.append(s) }
        }
        return out
    }

    /// The rest, without a final boundary.
    public mutating func end() -> String? {
        let s = String(buf).trimmingCharacters(in: .whitespacesAndNewlines)
        buf = []
        return s.isEmpty ? nil : s
    }

    public mutating func reset() { buf = [] }
    public var isEmpty: Bool { buf.allSatisfy { $0.isWhitespace } }

    private func boundary() -> Int? {
        for i in buf.indices {
            let c = buf[i]
            if c == "\n" { return i + 1 }
            if ".!?".contains(c), i + 1 < buf.count, buf[i + 1].isWhitespace, i + 1 >= minLen, !(i > 0 && buf[i - 1].isNumber) { return i + 1 }
        }
        return nil
    }
}

/// Voice choice helpers and per-sentence language (port of Android Voices.kt).
public enum Voices {
    static let de: Set<String> = ["der", "die", "das", "und", "ist", "nicht", "ich", "du", "ein", "eine", "mit", "für", "auf",
        "noch", "heute", "sind", "hat", "dir", "dein", "deine", "zu", "von", "es", "wir", "sie", "auch", "wie", "was",
        "wartet", "fertig", "gerade", "sitzung"]
    static let en: Set<String> = ["the", "and", "is", "not", "you", "your", "a", "with", "for", "on", "still", "today", "are",
        "has", "to", "of", "it", "we", "they", "was", "this", "that", "what", "how", "done", "waiting", "session"]

    /// "de" or "en" for one sentence by common words (umlauts count double), nil when it can't tell.
    public static func detect(_ text: String) -> String? {
        let words = SpeechText.words(text)
        let umlauts = text.lowercased().filter { "äöüß".contains($0) }.count
        let d = words.filter { de.contains($0) }.count + 2 * umlauts
        let e = words.filter { en.contains($0) }.count
        if d > e { return "de" }
        if e > d { return "en" }
        return nil
    }

    /// Language to speak `sentence` in: a fixed setting wins; "auto" detects, falling back to `fallback`.
    public static func langFor(_ sentence: String, setting: String, fallback: String = "de") -> String {
        if setting == "de" || setting == "en" { return setting }
        return detect(sentence) ?? fallback
    }

    /// Recognition locale for the setting "auto" | "de" | "en" (auto: the phone's first language when it is de or en, else de).
    public static func recognitionLocale(setting: String, preferred: [String]) -> String {
        switch setting {
        case "en": return "en-US"
        case "de": return "de-DE"
        default:
            if let first = preferred.first?.lowercased() {
                if first.hasPrefix("en") { return "en-US" }
            }
            return "de-DE"
        }
    }

    /// Ranking value of a voice for sorting: quality (1 default, 2 enhanced, 3 premium) first, home countries next.
    public static func rank(quality: Int, language: String, lang: String) -> Int {
        let home = lang == "de" ? ["de-DE"] : ["en-US", "en-GB"]
        let c = home.firstIndex(of: language).map { 10 - $0 } ?? 0
        return quality * 100 + c
    }
}

/// Speech post-processing: biasing list, choosing among the recogniser's hypotheses, known-mishearing fixes
/// (port of Android SpeechVocab.kt).
public enum SpeechVocab {
    /// Terms and the words of split titles ("work/api-merge" -> work, api, merge), short words dropped, deduplicated, capped.
    public static func biasing(_ terms: [String], cap: Int = 100) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: CharacterSet(charactersIn: ".+#"))
            guard t.count >= 3, seen.insert(t.lowercased()).inserted else { return }
            out.append(t)
        }
        for term in terms {
            let parts = term.split(whereSeparator: { !($0.isLetter || $0.isNumber || ".+#".contains($0)) }).map(String.init)
            if parts.count == 1 || (term.count <= 24 && !term.contains("/")) { add(term.trimmingCharacters(in: .whitespaces)) }
            if parts.count > 1 { parts.forEach(add) }
        }
        return Array(out.prefix(cap))
    }

    static func hasWord(_ text: String, _ w: String) -> Bool {
        var from = text.startIndex
        while let r = text.range(of: w, options: .caseInsensitive, range: from..<text.endIndex) {
            let before = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : nil
            let after = r.upperBound < text.endIndex ? text[r.upperBound] : nil
            if (before.map { !($0.isLetter || $0.isNumber) } ?? true) && (after.map { !($0.isLetter || $0.isNumber) } ?? true) { return true }
            from = text.index(after: r.lowerBound)
            if from >= text.endIndex { break }
        }
        return false
    }

    /// Confidence (rank-based when the recogniser gives none or 0) plus `bonus` per distinct vocabulary term in the hypothesis.
    /// Hypotheses much shorter than the longest one (under `minShare` of its length) are skipped: an alternative that
    /// covers only part of what was said must never win over the full one.
    public static func pick(_ hyps: [String], conf: [Float], terms: [String], bonus: Float = 0.12, minShare: Double = 0.6) -> String? {
        guard !hyps.isEmpty else { return nil }
        var seen = Set<String>()
        let vocab = terms.filter { $0.count >= 3 && seen.insert($0.lowercased()).inserted }
        let longest = hyps.map(\.count).max() ?? 0
        var best = 0
        var bestScore = -Float.infinity
        for (i, h) in hyps.enumerated() {
            if Double(h.count) < Double(longest) * minShare { continue }
            let c = (i < conf.count && conf[i] > 0) ? conf[i] : 1 - 0.05 * Float(i)
            let s = c + bonus * Float(vocab.filter { hasWord(h, $0) }.count)
            if s > bestScore + 1e-6 { best = i; bestScore = s }
        }
        return hyps[best]
    }

    private static func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Whole-word, case-insensitive, longest phrase first, single pass (a replacement is never corrected again).
    public static func correct(_ text: String, _ corrections: [(heard: String, meant: String)]) -> String {
        var map: [String: String] = [:]
        for c in corrections { let k = norm(c.heard); if !k.isEmpty { map[k] = c.meant } }
        guard !map.isEmpty else { return text }
        let alt = map.keys.sorted { $0.count > $1.count }.map { k in
            k.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s+"#)
        }.joined(separator: "|")
        guard let re = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])(?:"# + alt + #")(?![\p{L}\p{N}])"#, options: [.caseInsensitive]) else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let hit = ns.substring(with: m.range)
            out += map[norm(hit)] ?? hit
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Terms used to rate hypotheses: the biasing words plus what the corrections turn into.
    public static func scoringTerms(terms: [String], corrections: [(heard: String, meant: String)]) -> [String] {
        biasing(terms) + corrections.map(\.meant)
    }
}

/// One exchange with Jarvis, kept on the device.
/// Partial results of a dictation (SFSpeechRecognizer). After a pause the recogniser sometimes starts over on its own
/// without reporting `isFinal`: its next partial covers only the words after the pause, and the words before would be
/// lost. Such a restart is told from an ordinary revision by its shape: the new partial is much shorter than the last
/// one and does not begin like it.
public enum DictationText {
    /// The last partial is kept as committed text when `current` is less than half as long as `previous` (which has at
    /// least a few words) and does not start with the same letters.
    public static func restarted(previous: String, current: String) -> Bool {
        let o = norm(previous), n = norm(current)
        guard o.count >= 8, !n.isEmpty, n.count * 2 < o.count else { return false }
        let head = String(n.prefix(min(n.count, 6)))
        return !o.hasPrefix(head)
    }

    /// Letters and digits only, lower-cased, one space between words.
    static func norm(_ s: String) -> String {
        let kept = s.lowercased().map { ($0.isLetter || $0.isNumber) ? String($0) : " " }.joined()
        return kept.split(separator: " ").joined(separator: " ")
    }

    /// `a` and `b` with one space between, either may be empty.
    public static func join(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespaces), b = b.trimmingCharacters(in: .whitespaces)
        return a.isEmpty ? b : b.isEmpty ? a : a + " " + b
    }
}

public struct JarvisTurn: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var q: String
    public var a: String
    public var voice: Bool
    public var ts: Double
    public init(id: UUID = UUID(), q: String, a: String, voice: Bool, ts: Double = Date().timeIntervalSince1970) {
        self.id = id; self.q = q; self.a = a; self.voice = voice; self.ts = ts
    }
}

public enum JarvisHistory {
    public static let cap = 200

    /// Finished turns only (an answer that never arrived is not worth keeping), newest `cap`.
    public static func trimmed(_ turns: [JarvisTurn]) -> [JarvisTurn] {
        Array(turns.filter { !$0.a.isEmpty }.suffix(cap))
    }

    public static func encode(_ turns: [JarvisTurn]) -> Data? { try? JSONEncoder().encode(trimmed(turns)) }
    public static func decode(_ data: Data) -> [JarvisTurn] { (try? JSONDecoder().decode([JarvisTurn].self, from: data)) ?? [] }

    /// Every word of the query occurs in the turn (either side), any order, case-insensitive; newest first.
    public static func search(_ turns: [JarvisTurn], query: String) -> [JarvisTurn] {
        let ws = query.lowercased().split(separator: " ").map(String.init)
        guard !ws.isEmpty else { return [] }
        return turns.reversed().filter { t in
            let hay = (t.q + "\n" + t.a).lowercased()
            return ws.allSatisfy { hay.contains($0) }
        }
    }
}

/// Where the voice features stand, from `hello_ok.config.voice`.
public enum VoiceMode {
    /// True when the Desktop offers Jarvis Live (Gemini over the SSH `voice` channel). The iOS app does not use it.
    public static func isLive(_ configVoice: String?) -> Bool { configVoice == "live" }
}

/// Reading an answer aloud on demand (2026-11-07): the text the way a voice should say it, and the question inside an
/// answer with its options and recommendation, nothing else. Pure text rules, nothing leaves the phone.
public enum ReadAloud {
    static let codeNote = "Codeblock ausgelassen."

    /// Fenced code becomes a short note (a voice reading code is noise).
    static func stripCode(_ markdown: String) -> String {
        var t = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        t = t.replacingOccurrences(of: #"```[\s\S]*?```"#, with: "\n\(codeNote)\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"```[\s\S]*$"#, with: "\n\(codeNote)\n", options: .regularExpression)  // never closed
        return t
    }

    /// Markdown made speakable: fenced code a short note, inline code its words, links their text, bare URLs "Link", file
    /// paths their last part (`/home/x/docs/nachtlog.md` -> "nachtlog.md"), tables their cells with commas, headings,
    /// list marks, quotes, rules and emphasis gone. "km/h" and "und/oder" are no paths and stay.
    public static func cleaned(_ markdown: String) -> String {
        var t = stripCode(markdown)
        t = t.replacingOccurrences(of: #"`([^`\n]*)`"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"!\[([^\]\n]*)\]\([^)\n]*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]\n]*)\]\([^)\n]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<(?:https?://|www\.)[^>\s]+>"#, with: "Link", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"(?:https?://|www\.)[^\s<>()\[\]"']+"#, with: "Link", options: [.regularExpression, .caseInsensitive])
        t = replacing(t, absolutePath) { pathName($0) }
        t = replacing(t, relativeFile) { pathName($0) }
        var lines: [String] = []
        for raw in t.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#, options: .regularExpression) != nil { continue }  // table separator
            if line.range(of: #"^([-*_]\s*){3,}$"#, options: .regularExpression) != nil { continue }  // rule
            if line.hasPrefix("|") || line.filter({ $0 == "|" }).count >= 2 {
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                line = cells.isEmpty ? "" : cells.joined(separator: ", ") + "."
            }
            line = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^[-*+•]\s+(\[[ xX]\]\s*)?"#, with: "", options: .regularExpression)
            lines.append(line)
        }
        t = lines.joined(separator: "\n")
        t = t.replacingOccurrences(of: #"</?[a-zA-Z][^>\n]*>"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\*\*|__|~~|[*`]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #" +\n"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // a path segment: word characters, a dot only when a word character follows (so a sentence's full stop stays)
    private static let segment = #"(?:[\w@+~-]|\.(?=\w))+"#
    /// `/usr/x`, `~/x/y`, `./x`, `../x`, with an optional `:line` or `:line:col`; not "km/h" or "und/oder".
    private static let absolutePath = #"(?<![\w/.])(?:~|\.{1,2})?(?:/"# + segment + #")+/?(?::\d+(?::\d+)?)?"#
    /// `docs/nachtlog.md`, `scripts/make_source.py`: a relative path whose last part is a file with an extension.
    private static let relativeFile = #"(?<![\w/.])[\w@+~-]+(?:/[\w@+~-]+)*/[\w@+~-]+\.[A-Za-z0-9]{1,6}\b(?::\d+(?::\d+)?)?"#

    /// The last part of a path without a line number; "Pfad" when there is none worth saying.
    static func pathName(_ path: String) -> String {
        var s = path.replacingOccurrences(of: #":\d+(?::\d+)?$"#, with: "", options: .regularExpression)
        while s.hasSuffix("/") { s.removeLast() }
        let name = s.split(separator: "/").last.map(String.init) ?? ""
        if name.isEmpty || name == "~" || name == "." || name == ".." { return "Pfad" }
        return name
    }

    static func replacing(_ s: String, _ pattern: String, _ f: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f(ns.substring(with: m.range))
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    // MARK: the question in an answer

    static func paragraphs(_ t: String) -> [String] {
        t.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func isListItem(_ line: String) -> Bool {
        line.range(of: #"^\s*(?:[-*+•]\s+|\d{1,2}[.)]\s+|[a-hA-H][.)]\s+|Option\s+\w)"#, options: .regularExpression) != nil
    }

    /// A paragraph of list items, with at most one intro line ("Optionen:") before them.
    static func isList(_ p: String) -> Bool {
        let lines = p.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { return false }
        let items = isListItem(first) ? lines : Array(lines.dropFirst())
        return !items.isEmpty && items.allSatisfy(isListItem)
    }

    /// It asks something: a question mark, or it opens like a decision ("Frage:", "Soll ich", "Entscheidung").
    static func isQuestion(_ p: String) -> Bool {
        if p.contains("?") { return true }
        let l = p.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "*_# "))
        return ["frage", "rückfrage", "entscheidung", "soll ich", "willst du", "möchtest du", "sollen wir", "question"].contains { l.hasPrefix($0) }
    }

    static func isRecommendation(_ p: String) -> Bool {
        let l = p.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "*_# "))
        return ["empfehlung", "ich empfehle", "mein vorschlag", "vorschlag:", "recommendation"].contains { l.hasPrefix($0) }
            || l.contains("ich empfehle") || l.contains("meine empfehlung")
    }

    /// The question of an answer with its options and recommendation: the last paragraph that asks something, a list
    /// right before it (the options it refers to, with their intro line) and the lists, further questions and the
    /// recommendation after it; a recommendation further down still counts. Nil when the answer asks nothing. Works on
    /// the text without code, so a question inside a code block never counts.
    public static func question(in markdown: String) -> String? {
        let paras = paragraphs(stripCode(markdown))
        guard let qi = paras.lastIndex(where: isQuestion) ?? paras.lastIndex(where: isRecommendation) else { return nil }
        var picked = [qi]
        if qi > 0, isList(paras[qi - 1]) {
            picked.insert(qi - 1, at: 0)
            if qi > 1, paras[qi - 2].hasSuffix(":") { picked.insert(qi - 2, at: 0) }
        }
        var j = qi + 1
        while j < paras.count, isList(paras[j]) || isRecommendation(paras[j]) || isQuestion(paras[j]) { picked.append(j); j += 1 }
        if let r = (j..<paras.count).first(where: { isRecommendation(paras[$0]) }) { picked.append(r) }
        let text = cleaned(picked.map { paras[$0] }.joined(separator: "\n\n"))
        return text.rangeOfCharacter(from: .alphanumerics) == nil ? nil : text
    }

    /// An agent's question from `rueckfrage` as it should be read: the question and the recommendation, no context.
    public static func spoken(_ q: AgentQuestion) -> String {
        var parts = [q.question]
        if !q.recommendation.isEmpty { parts.append("Empfehlung: " + q.recommendation) }
        return cleaned(parts.joined(separator: "\n"))
    }

    /// The session's open question (its card) with the numbered options and their descriptions.
    public static func spoken(question q: Question) -> String {
        var lines: [String] = []
        for sub in q.all {
            lines.append(sub.text)
            for (i, o) in sub.options.enumerated() {
                lines.append("\(i + 1). " + o.label + (o.description.isEmpty ? "" : ": " + o.description))
            }
        }
        return cleaned(lines.joined(separator: "\n"))
    }

    /// The newest message of the agent with text ("letzte Antwort vorlesen").
    public static func lastAnswer(_ messages: [TMessage]) -> TMessage? {
        messages.last { $0.role == "assistant" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
