import Foundation

// Pure logic of writing in a chat: answer keys for the question form, slash chips and quick replies, the outbox,
// attachment sizes, the working line and the chat header. Port of Answers.kt, SlashChips.kt, ChatText.kt (SlashCatalog),
// Outbox.kt (OutboxLogic), Attach.kt, Running.kt.

// MARK: question form

/// One step of an answer typed into the TUI: a tmux key name, or text pasted without Enter (`send` `steps`).
public enum Step: Sendable, Equatable {
    case key(String)
    case text(String)

    public var json: JSON {
        switch self {
        case .key(let k): return .string(k)
        case .text(let t): return .object(["text": .string(t)])
        }
    }
}

/// What the user chose in one question of a form: options (0-based) and/or a free text ("Etwas anderes...";
/// `other` nil: its field is closed). In a single-select question an option and a typed answer replace each other.
public struct Pick: Sendable, Equatable {
    public var options: Set<Int>
    public var other: String?
    public init(options: Set<Int> = [], other: String? = nil) { self.options = options; self.other = other }

    public var text: String { other?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    public func choose(_ i: Int, multi: Bool) -> Pick {
        if multi {
            var o = options
            if o.contains(i) { o.remove(i) } else { o.insert(i) }
            return Pick(options: o, other: other)
        }
        return Pick(options: [i])
    }

    public func typing(multi: Bool) -> Pick {
        if other != nil { return Pick(options: options, other: nil) }
        if multi { return Pick(options: options, other: "") }
        return Pick(other: "")
    }
}

public extension Question {
    /// The gateway sent every question of a form (an older one sends only the first).
    var complete: Bool { !questions.isEmpty && questions.count == count }
}

/// Keys that answer Claude Code's AskUserQuestion picker (confirmed on a live pane by the Android app, Answers.kt):
/// single-select: the option's digit; free text: the digit of "Type something" (options + 1), the text, Enter;
/// multi-select: digits only tick, then Down to the Submit row and Enter; a form or a multi-select ends on a review
/// tab whose "1" submits. The gateway sends the steps one by one, and only while the question is still the open one.
public enum AnswerKeys {
    public static func usable(_ q: Question?) -> Bool {
        guard let q else { return false }
        return !q.multi && q.count == 1 && (1...9).contains(q.options.count)
    }

    public static func formUsable(_ q: Question?) -> Bool {
        guard let q, q.complete else { return false }
        return q.all.allSatisfy { (1...8).contains($0.options.count) }
    }

    public static func option(_ index: Int) -> [String] { [String(index + 1)] }

    public static func sendParams(key: String, index: Int, question: String) -> JSON {
        .object(["key": .string(key), "keys": JSON(option(index)), "force": true, "expect_question": .string(question)])
    }

    public static func answered(_ q: Question, _ p: Pick) -> Bool {
        !p.text.isEmpty || (q.multi ? !p.options.isEmpty : p.options.count == 1)
    }

    /// The steps that answer every question of `form` with `picks` (same order) and submit it. nil when one is unanswered.
    public static func steps(_ form: [Question], _ picks: [Pick]) -> [Step]? {
        guard form.count == picks.count, form.indices.allSatisfy({ answered(form[$0], picks[$0]) }) else { return nil }
        var out: [Step] = []
        for (i, q) in form.enumerated() {
            let p = picks[i]
            let n = q.options.count
            if !q.multi {
                if !p.text.isEmpty { out += [.key("\(n + 1)"), .text(p.text), .key("Enter")] }
                else if let o = p.options.first { out.append(.key("\(o + 1)")) }
            } else {
                for o in p.options.sorted() { out.append(.key("\(o + 1)")) }
                if !p.text.isEmpty {
                    out += Array(repeating: Step.key("Down"), count: n)
                    out += [.text(p.text), .key("Down")]
                } else {
                    out += Array(repeating: Step.key("Down"), count: n + 1)
                }
                out.append(.key("Enter"))
            }
        }
        if form.count > 1 || form.contains(where: { $0.multi }) { out.append(.key("1")) }
        return out
    }

    public static func stepsParams(key: String, question q: Question, picks: [Pick]) -> JSON? {
        guard let s = steps(q.all, picks) else { return nil }
        return .object(["key": .string(key), "steps": .array(s.map(\.json)), "force": true, "expect_question": .string(q.text)])
    }

    /// Esc: "User declined to answer questions".
    public static func declineParams(key: String, question q: Question) -> JSON {
        .object(["key": .string(key), "keys": ["Escape"], "force": true, "expect_question": .string(q.text)])
    }
}

// MARK: slash chips and quick replies

public enum SlashChips {
    public static let tools = ["claude", "codex", "agy"]
    public static let defaults: [String: String] = [
        "claude": "/compact /clear /model /usage /resume /cost",
        "codex": "/model /status /compact /new",
        "agy": "/model /help",
    ]
    public static func parse(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}

public enum SlashCatalog {
    static let builtin: [String: [String]] = [
        "claude": ["/clear", "/compact", "/context", "/cost", "/usage", "/model", "/effort", "/resume", "/rewind", "/memory",
                   "/permissions", "/config", "/status", "/mcp", "/agents", "/hooks", "/init", "/review", "/export", "/doctor",
                   "/help", "/add-dir", "/rename"],
        "codex": ["/model", "/approvals", "/status", "/new", "/compact", "/diff", "/mention", "/init", "/review", "/quit"],
        "agy": ["/model", "/help", "/clear", "/mcp"],
    ]

    /// The user's chips first, then the tool's standard commands, each once.
    public static func forTool(_ tool: String, user: [String]) -> [String] {
        var seen = Set<String>()
        return (user + (builtin[tool] ?? [])).filter { seen.insert($0).inserted }
    }

    /// Suggestions for `text`: only while it starts with "/" and holds no white space; at most 10.
    public static func matches(_ all: [String], _ text: String) -> [String] {
        guard text.hasPrefix("/"), !text.contains(where: { $0.isWhitespace }) else { return [] }
        return Array(all.filter { $0.lowercased().hasPrefix(text.lowercased()) && $0 != text }.prefix(10))
    }
}

public enum QuickReplies {
    public static let standard = "Weiter|Ja|Status?"
    public static func parse(_ s: String) -> [String] {
        var seen = Set<String>()
        let all = s.split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return Array(all.prefix(8))
    }
}

// MARK: outbox

public enum OutState: String, Sendable { case queued, sending, delivered, failed }

/// A message on its way to the Desktop. `id` doubles as the `client_id` of the `send` (a second send with the same
/// id gets the first one's answer, so repeating after a lost answer is harmless).
public struct OutItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let key: String
    public let text: String
    public let at: Double
    public var state: OutState
    public var error: String?
    public var tries: Int
    public var doneAt: Double
    public var force: Bool
    /// `send {move:true}`: die Sitzung am PC (Terminal ohne tmux) beenden und in tmux mit dieser Nachricht fortsetzen.
    public var move: Bool

    public init(id: String, key: String, text: String, at: Double, state: OutState = .queued, error: String? = nil,
                tries: Int = 0, doneAt: Double = 0, force: Bool = false, move: Bool = false) {
        self.id = id; self.key = key; self.text = text; self.at = at; self.state = state; self.error = error
        self.tries = tries; self.doneAt = doneAt; self.force = force; self.move = move
    }

    public var json: JSON {
        .obj(["id": .string(id), "key": .string(key), "text": .string(text), "at": .number(at), "state": .string(state.rawValue),
              "error": error.map { .string($0) }, "tries": .number(Double(tries)), "done_at": .number(doneAt), "force": .bool(force),
              "move": move ? .bool(true) : nil])
    }

    public static func from(_ o: JSON) -> OutItem? {
        let id = o.str("id"), key = o.str("key"), text = o.str("text")
        guard !id.isEmpty, !key.isEmpty, !text.isEmpty else { return nil }
        return OutItem(id: id, key: key, text: text, at: o.num("at"), state: OutState(rawValue: o.str("state")) ?? .queued,
                       error: o["error"].string, tries: o["tries"].int ?? 0, doneAt: o.num("done_at"), force: o.flag("force"),
                       move: o.flag("move"))
    }
}

public enum OutboxLogic {
    public static let deliveredKeep: Double = 10 * 60

    /// Waiting between two attempts: 20 s << min(waits, 4), at most 300 s.
    public static func wait(_ waits: Int) -> Double { min(20.0 * Double(1 << min(max(waits, 0), 4)), 300) }

    public static func next(_ items: [OutItem]) -> OutItem? { items.first { $0.state == .queued } }

    /// Offline, link lost, timed out: try again. The gateway saying no won't change by itself.
    public static func retries(_ e: Error) -> Bool { (e as? RelayError).map { !$0.remote } ?? true }

    /// The user's "Wiederholen" or "Trotzdem senden" on a failed item: queued again, with `force` when given. A failed
    /// one gets a new id, because the gateway answers a known `client_id` with its first (refusing) answer; a queued
    /// one keeps its id, so a send whose answer got lost is never typed twice.
    public static func retried(_ i: OutItem, force: Bool?, newId: String, move: Bool? = nil) -> OutItem {
        OutItem(id: i.state == .failed ? newId : i.id, key: i.key, text: i.text, at: i.at, state: .queued, error: nil,
                tries: i.tries, doneAt: 0, force: force ?? i.force, move: move ?? i.move)
    }

    /// The list as it is kept on disk: delivered ones are done, a send cut off by the app's end counts as not sent.
    public static func restored(_ items: [OutItem]) -> [OutItem] {
        items.filter { $0.state != .delivered }.map { i in var c = i; if c.state == .sending { c.state = .queued }; return c }
    }

    public static func encode(_ items: [OutItem]) -> Data {
        Data(JSON.array(items.map(\.json)).serialized().utf8)
    }

    public static func decode(_ data: Data) -> [OutItem] {
        (JSON.parse(data)?.array ?? []).compactMap(OutItem.from)
    }

    /// Delivered items the transcript shows by now (a user message with the same text) or that are old.
    public static func sweep(_ items: [OutItem], seen texts: [String], now: Double) -> [OutItem] {
        let t = Set(texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        return items.filter { i in
            guard i.state == .delivered else { return true }
            if now - i.doneAt > deliveredKeep { return false }
            return !t.contains(i.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The line under a message that isn't in the transcript yet.
    public static func status(_ i: OutItem, connected: Bool, network: Bool) -> String {
        switch i.state {
        case .delivered: return "gesendet"
        case .failed:
            if isBusyRefusal(i.error ?? "") { return "Nicht gesendet: die Sitzung arbeitet gerade" }
            if DeskTerminal.isRefusal(i.error ?? "") { return DeskTerminal.statusText }
            if SubmitCheck.isStuck(i.error ?? "") { return "Nicht abgeschickt: " + SubmitCheck.short }
            return "Nicht gesendet: " + (i.error ?? "abgelehnt").replacingOccurrences(of: "not sent: ", with: "")
        case .sending: return "sendet…"
        case .queued:
            if connected { return "sendet…" }
            return network ? "wartet auf Verbindung" : "wartet auf Netz"
        }
    }

    /// A refusal because the session works (`send` without `force`): "Trotzdem senden" retries with force.
    public static func isBusyRefusal(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("busy") || m.contains("arbeitet") || m.contains("working")
    }
}

// MARK: dictation and sending

/// "Senden" while dictating: the button stays active, the microphone stays on for `grace` so the recogniser catches
/// the last words, then typed and spoken text go out together.
public enum DictationSend {
    /// Seconds the microphone stays on after "Senden" was tapped.
    public static let grace: TimeInterval = 2

    /// Longest wait after "Senden" during a dictation for the words to arrive (the dictation's end, the clean-up on the
    /// Desktop); then the button is freed with whatever is in the field, so the chat never stays blocked.
    public static let stuckAfter: TimeInterval = 25

    /// The send button: text in the field, or a running dictation (its words are sent once it ends); never while sending.
    public static func canSend(input: String, listening: Bool, sending: Bool, hasSession: Bool) -> Bool {
        hasSession && !sending && (listening || !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// What follows a dictation that ended with "Senden" pending: the field's text goes out, or the user is told why not
    /// (nothing recognised, or the recogniser's error). Nothing is ever dropped without a word.
    public enum Outcome: Equatable, Sendable { case send(String), nothing(String) }

    public static func afterDictation(field: String, failure: String?) -> Outcome {
        let t = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return .send(t) }
        if let f = failure?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty { return .nothing("Nicht gesendet: \(f)") }
        return .nothing("Nichts verstanden, nichts gesendet.")
    }
}

// MARK: attachments

public enum Attach {
    public static let outEdge = 2048
    public static let quality = 0.85
    public static let maxBytes = 50 * 1024 * 1024
    static let imageExt: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "avif"]
    static let videoExt: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]

    static func ext(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }
    public static func isImage(_ name: String, mime: String? = nil) -> Bool { mime?.hasPrefix("image/") == true || imageExt.contains(ext(name)) }
    public static func isVideo(_ name: String, mime: String? = nil) -> Bool { mime?.hasPrefix("video/") == true || videoExt.contains(ext(name)) }
    public static func isGif(_ name: String, mime: String? = nil) -> Bool { mime == "image/gif" || ext(name) == "gif" }

    /// Photos with a long edge above 2048 px are re-encoded; GIFs (animation) and non-images never.
    public static func needsResize(name: String, mime: String? = nil, width: Int, height: Int) -> Bool {
        isImage(name, mime: mime) && !isGif(name, mime: mime) && max(width, height) > outEdge
    }

    /// Size with the long edge at 2048; never enlarged.
    public static func targetSize(_ w: Int, _ h: Int) -> (Int, Int) {
        let long = max(w, h)
        if long <= outEdge { return (w, h) }
        let f = Double(outEdge) / Double(long)
        return (max(1, Int((Double(w) * f).rounded())), max(1, Int((Double(h) * f).rounded())))
    }

    public static func jpegName(_ name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        return (base.isEmpty ? "foto" : base) + ".jpg"
    }

    /// The message that goes into the session: typed text, then one Desktop path per line.
    public static func body(_ text: String, _ paths: [String]) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = paths.joined(separator: "\n")
        return t.isEmpty ? p : (p.isEmpty ? t : t + "\n\n" + p)
    }
}

// MARK: working line

/// Something a session runs now (rpc `running`): a subagent, a long command, a background shell, agent, monitor, workflow.
public struct RunningItem: Sendable, Equatable, Identifiable {
    public let id: String, kind: String, label: String
    public let since: Double
    public let background: Bool
    public let activity: String

    public static func list(from o: JSON) -> [RunningItem] {
        o["running"].array.compactMap { r in
            let id = r.str("id"); guard !id.isEmpty else { return nil }
            let label = r.str("label")
            return RunningItem(id: id, kind: r.str("kind", "task"), label: label.isEmpty ? "Aufgabe" : label, since: r.num("since"),
                               background: r.flag("background"), activity: r.str("activity"))
        }
    }
}

/// The TUI's spinner line while the agent works: "Computing... (4m 49s, 7.3k tokens)".
public struct LiveStatus: Sendable, Equatable {
    public let verb: String, elapsed: String, tokens: String
    public init(verb: String, elapsed: String = "", tokens: String = "") { self.verb = verb; self.elapsed = elapsed; self.tokens = tokens }
    public static func from(_ o: JSON) -> LiveStatus? {
        let s = o["status"]
        let v = s.str("verb")
        return v.isEmpty ? nil : LiveStatus(verb: v, elapsed: s.str("elapsed"), tokens: s.str("tokens"))
    }
}

public enum RunningText {
    public static func icon(_ kind: String) -> String {
        switch kind { case "agent": return "person.2"; case "shell": return "terminal"; case "monitor": return "eye"; case "workflow": return "gearshape.2"; default: return "circle.dotted" }
    }

    public static func what(_ r: RunningItem) -> String {
        switch r.kind {
        case "agent": return r.background ? "Hintergrund-Agent" : "Subagent"
        case "shell": return r.background ? "Hintergrund-Shell" : "Befehl"
        case "monitor": return "Monitor"
        case "workflow": return "Workflow"
        default: return r.background ? "Hintergrundaufgabe" : r.kind
        }
    }

    /// "2 Agenten, 1 Shell" for the working line.
    public static func summary(_ items: [RunningItem]) -> String {
        func group(_ k: String) -> String { k == "agent" || k == "shell" || k == "workflow" ? k : "task" }
        var n: [String: Int] = [:]
        for i in items { n[group(i.kind), default: 0] += 1 }
        let names: [(String, String, String)] = [("agent", "Agent", "Agenten"), ("workflow", "Workflow", "Workflows"),
                                                 ("shell", "Shell", "Shells"), ("task", "Aufgabe", "Aufgaben")]
        return names.compactMap { k, one, many in n[k].map { "\($0) \($0 == 1 ? one : many)" } }.joined(separator: ", ")
    }

    /// "jetzt", "45 s", "3 min", "1 h 5 min".
    public static func elapsed(since: Double, now: Double) -> String {
        if since <= 0 { return "" }
        let s = Int(max(0, now - since))
        if s < 5 { return "jetzt" }
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min" }
        let m = s % 3600 / 60
        return "\(s / 3600) h" + (m > 0 ? " \(m) min" : "")
    }

    /// "(4m 49s, 7.3k tokens)" after the verb; "" when there is nothing to say.
    public static func info(_ st: LiveStatus?) -> String {
        let parts = [st?.elapsed ?? "", st?.tokens ?? ""].filter { !$0.isEmpty }
        return parts.isEmpty ? "" : "(" + parts.joined(separator: " · ") + ")"
    }

    private static func norm(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }) }

    /// The reply being written, unless the transcript has it already (its newest reply starts the same way).
    public static func freshPreview(_ preview: String, lastReply: String) -> String {
        let p = String(norm(preview).prefix(60))
        if p.count < 8 { return preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : preview }
        return norm(lastReply).contains(p) ? "" : preview
    }
}

// MARK: Tastatur und Lesemodus

/// Knopf „Tastatur ausblenden“ im Chat (2026-11-07): Er schließt die Tastatur, Text und Diktat bleiben dabei.
/// Seit 0.3.8 sitzt er nicht mehr in der Leiste über der Tastatur (dort lag er über Senden und Mikrofon), sondern am
/// rechten Ende der Schnellantwort-Zeile. Ohne Schnellantworten bekommt er eine eigene schmale Zeile darüber.
public enum KeyboardBar {
    public static let hideLabel = "Tastatur ausblenden"
    /// Mindestgröße der Tippfläche (Apple: 44 pt).
    public static let minTapSize: Double = 44

    /// Was die Zeile über dem Eingabefeld zeigt.
    public struct Row: Equatable, Sendable {
        public let quickReplies: Bool, hideButton: Bool
        public init(quickReplies: Bool, hideButton: Bool) { self.quickReplies = quickReplies; self.hideButton = hideButton }
        /// Die Zeile erscheint überhaupt nur, wenn sie etwas zeigt.
        public var visible: Bool { quickReplies || hideButton }
    }

    /// Schnellantworten stehen, sofern eingestellt und keine Slash-Vorschläge offen sind. Der Knopf erscheint nur bei
    /// offener Tastatur, auch während Slash-Vorschläge offen sind.
    public static func row(quickCount: Int, keyboardOpen: Bool, slashSuggestions: Bool) -> Row {
        Row(quickReplies: quickCount > 0 && !slashSuggestions, hideButton: keyboardOpen)
    }
}

/// Lesemodus im Chat (2026-11-07): Navigationsleiste, Eingabezeile und Tastatur verschwinden, der Verlauf füllt den
/// Bildschirm; ein kleiner Knopf oben rechts bringt die normale Ansicht zurück.
public enum ReadingMode {
    public static let enterLabel = "Lesemodus"
    public static let exitLabel = "Lesemodus beenden"

    /// Was die Ansicht zeigt.
    public struct Chrome: Equatable, Sendable {
        public let navigationBar: Bool, inputBar: Bool
        public init(navigationBar: Bool, inputBar: Bool) { self.navigationBar = navigationBar; self.inputBar = inputBar }
    }

    public static func chrome(reading: Bool) -> Chrome {
        Chrome(navigationBar: !reading, inputBar: !reading)
    }

    /// Umschalten: in den Lesemodus hinein geht die Tastatur zu (der Text im Feld bleibt), heraus bleibt sie zu.
    public static func toggle(reading: Bool) -> (reading: Bool, closesKeyboard: Bool) { (!reading, !reading) }
}

// MARK: chat header

public enum ChatHeader {
    /// "/home/martin/relay" -> "~/relay"; "/home/martin" -> "~"; anything else unchanged.
    public static func shortPath(_ cwd: String) -> String {
        let parts = cwd.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count >= 2, parts[0] == "home" {
            let rest = parts.dropFirst(2)
            return rest.isEmpty ? "~" : "~/" + rest.joined(separator: "/")
        }
        return cwd
    }

    public static func toolName(_ tool: String) -> String {
        switch tool { case "claude": return "Claude"; case "codex": return "Codex"; case "agy": return "Antigravity"; default: return tool.capitalized }
    }

    /// "opus 5.5 · low effort · Claude · ~/ordner · 120k ctx"; model, effort and context come after the first request.
    public static func subtitle(model: String, effort: String, tool: String, cwd: String, tokens: Int?) -> String {
        var parts: [String] = []
        let m = ContextText.model(model)
        if !m.isEmpty { parts.append(m) }
        if !effort.isEmpty { parts.append("\(effort) effort") }
        parts.append(toolName(tool))
        if !cwd.isEmpty { parts.append(shortPath(cwd)) }
        if let t = tokens, t > 0 { parts.append(ContextText.tokens(t) + " ctx") }
        return parts.joined(separator: " · ")
    }

    public static let models = ["opus", "sonnet", "haiku"]
    public static let efforts = ["low", "medium", "high", "xhigh", "max"]
}
