import Foundation

// Plain model of PROTOCOL.md (v2), mirroring the Android app's Protocol.kt.

public struct QOption: Sendable, Hashable { public let label: String; public let description: String }

/// Claude's AskUserQuestion while the session waits (`session.question`).
public struct Question: Sendable, Hashable {
    public let text: String
    public let header: String
    public let options: [QOption]
    public let multi: Bool
    public let count: Int
    public let questions: [Question]

    public var all: [Question] { questions.isEmpty ? [self] : questions }

    public static func from(_ o: JSON) -> Question? {
        let text = o.str("question")
        guard !text.isEmpty else { return nil }
        let opts = o["options"].array.compactMap { q -> QOption? in
            let l = q.str("label"); return l.isEmpty ? nil : QOption(label: l, description: q.str("description"))
        }
        let qs = o["questions"].array.compactMap { Question.from($0) }.map {
            Question(text: $0.text, header: $0.header, options: $0.options, multi: $0.multi, count: 1, questions: [])
        }
        return Question(text: text, header: o.str("header"), options: opts, multi: o.flag("multi"),
                        count: o["count"].int ?? 1, questions: qs)
    }
}

public struct SessionContext: Sendable, Hashable {
    public let tokens: Int, window: Int, pct: Int, level: String, model: String
    public static func from(_ o: JSON) -> SessionContext? {
        guard let t = o["tokens"].int, t > 0 else { return nil }
        return SessionContext(tokens: t, window: o["window"].int ?? 0, pct: o["pct"].int ?? 0, level: o.str("level", "ok"), model: o.str("model"))
    }
    public var label: String { [ContextText.model(model), ContextText.tokens(tokens) + " ctx"].filter { !$0.isEmpty }.joined(separator: " · ") }
}

public enum ContextText {
    public static func model(_ id: String) -> String {
        guard !id.isEmpty else { return "" }
        // claude-opus-5-5[-date] -> "opus 5.5"
        let parts = id.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
        if parts.count >= 3, Int(parts[1]) != nil, let minor = Int(parts[2]), minor < 100 { return "\(parts[0]) \(parts[1]).\(parts[2])" }
        return id.replacingOccurrences(of: "claude-", with: "")
    }
    public static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000 { return "\(n / 1000)k" }
        return "\(n)"
    }
}

public struct Session: Sendable, Hashable, Identifiable {
    public var id: String { key }
    public let key: String, tool: String, alias: String, sid: String, label: String
    public let cwd: String, title: String
    public var state: String
    public let alive: Bool, attachable: Bool
    public let tmuxSession: String?
    public let lastActivity: Double
    public let lastMessage: String
    public let duplicates: Int
    public let remoteUrl: String
    public let background: Bool
    public let question: Question?
    public let hibernated: Bool
    public let closed: Bool
    public let closedReason: String
    public let seenAt: Double
    public let context: SessionContext?
    public var asks: Bool
    public let asksText: String

    public var name: String { title.isEmpty ? String(sid.prefix(8)) : title }
    public var asksYou: Bool { asks && state == "idle" }
    public var waits: Bool { state == "needs_input" || asksYou }
    public var shownState: String { asksYou ? "needs_input" : state }
    public var folder: String {
        let t = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        return t.split(separator: "/").last.map(String.init) ?? cwd
    }
    public var exited: Bool { state == "exited" }
    public var placeholder: Bool { sid.hasPrefix("tmux-") }
    public var liveTmux: String? { exited ? nil : tmuxSession }
    /// `send`/`screen` address: the tmux session while it runs, else the key (a message to a dormant session resumes it).
    public var target: String { liveTmux.map { "tmux:\($0)" } ?? key }

    public func matches(_ ref: String) -> Bool {
        if key == ref { return true }
        guard let t = tmuxSession else { return false }
        return ref == "tmux:\(t)" || ref == "\(tool):\(alias):tmux-\(t)"
    }

    public static func from(_ o: JSON) -> Session? {
        let key = o.str("key")
        guard !key.isEmpty else { return nil }
        let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
        func part(_ i: Int) -> String { parts.indices.contains(i) ? parts[i] : "" }
        let tmux = o["tmux_session"].string
        return Session(
            key: key, tool: o.str("tool", part(0)), alias: o.str("alias", part(1)), sid: o.str("id", part(2)),
            label: o.str("label"), cwd: o.str("cwd"), title: o.str("title"), state: o.str("state", "idle"),
            alive: o.flag("alive", true), attachable: o.flag("attachable"),
            tmuxSession: (tmux?.isEmpty ?? true) ? nil : tmux,
            lastActivity: o.num("last_activity"), lastMessage: o.str("last_message"),
            duplicates: o["duplicates"].int ?? 1, remoteUrl: o.str("remote_url"), background: o.flag("background"),
            question: Question.from(o["question"]), hibernated: o.flag("hibernated"), closed: o.flag("closed"), closedReason: o.str("closed_reason"),
            seenAt: o.num("seen_at"), context: SessionContext.from(o["context"]),
            asks: o.flag("asks"), asksText: o.str("asks_text"))
    }
}

public struct Account: Sendable, Hashable, Identifiable {
    public var id: String { alias }
    public let alias: String, tool: String, label: String, home: String, loggedIn: Bool
    public static func from(_ o: JSON) -> Account? {
        let a = o.str("alias"); guard !a.isEmpty else { return nil }
        return Account(alias: a, tool: o.str("tool"), label: o.str("label", a), home: o.str("home"), loggedIn: o.flag("logged_in", true))
    }
}

public struct ToolCall: Sendable, Hashable { public let name: String; public let summary: String; public let path: String? }

public struct RemoteFile: Sendable, Hashable {
    public let path: String, name: String, size: Int, mime: String, kind: String
    public static func from(_ o: JSON) -> RemoteFile? {
        let p = o.str("path"); guard !p.isEmpty else { return nil }
        return RemoteFile(path: p, name: o.str("name", (p as NSString).lastPathComponent), size: o["size"].int ?? -1,
                          mime: o.str("mime"), kind: o.str("kind"))
    }
}

public struct TMessage: Sendable, Hashable, Identifiable {
    public let id: String, role: String, text: String
    public let tools: [ToolCall]
    public let ts: Double
    public let files: [RemoteFile]
    public static func from(_ o: JSON) -> TMessage {
        TMessage(id: o.str("id", UUID().uuidString), role: o.str("role", "assistant"), text: o.str("text"),
                 tools: o["tools"].array.map { ToolCall(name: $0.str("name", "tool"), summary: $0.str("summary"), path: $0["path"].string) },
                 ts: o.num("ts"), files: o["files"].array.compactMap(RemoteFile.from))
    }
}

// MARK: screen menus (gateway tuimenu.py)

public struct MenuOption: Sendable, Hashable {
    public let label: String, description: String
    public let n: Int?
    public let current: Bool
    public let checked: Bool?
    public let input: Bool
}
public struct MenuAction: Sendable, Hashable { public let label: String; public let keys: [String] }

public enum PanelBlock: Sendable, Hashable {
    case text(String)
    case rows([(text: String, detail: String, cursor: Bool)])
    case kv([(String, String)])
    case bar(label: String, pct: Int, text: String)
    case box(String)
    case mono(String)

    public static func == (a: PanelBlock, b: PanelBlock) -> Bool { a.hashKey == b.hashKey }
    public func hash(into h: inout Hasher) { h.combine(hashKey) }
    private var hashKey: String {
        switch self {
        case .text(let t): return "t" + t
        case .rows(let r): return "r" + r.map { "\($0.text)|\($0.detail)|\($0.cursor)" }.joined(separator: "\n")
        case .kv(let r): return "k" + r.map { "\($0.0)=\($0.1)" }.joined(separator: "\n")
        case .bar(let l, let p, let t): return "b\(l)\(p)\(t)"
        case .box(let t): return "x" + t
        case .mono(let t): return "m" + t
        }
    }

    static func from(_ o: JSON) -> PanelBlock? {
        switch o.str("type") {
        case "text": return .text(o.str("text"))
        case "rows": return .rows(o["rows"].array.map { ($0.str("text"), $0.str("detail"), $0.flag("cursor")) })
        case "kv": return .kv(o["rows"].array.map { ($0[0].string ?? "", $0[1].string ?? "") })
        case "bar": return .bar(label: o.str("label"), pct: o["pct"].int ?? 0, text: o.str("text"))
        case "box": return .box(o.str("text"))
        case "mono": return .mono(o.str("text"))
        default: return nil
        }
    }
}

public struct ScreenMenu: Sendable, Hashable {
    public let id: String, kind: String, title: String, text: String
    public let options: [MenuOption]
    public let cursor: Int?
    public let scrolls: Bool
    public let multi: Bool
    public let digits: Bool
    public let body: String, box: String, footer: String, plan: String
    public let actions: [MenuAction]
    public let blocks: [PanelBlock]
    public let tabs: [String]
    public let nav: Bool
    public let otherN: Int?
    public let submit: String?

    public var isPanel: Bool { kind == "panel" }
    public var numbered: Bool { options.contains { $0.n != nil } }
    /// Index in `options` of the row the TUI's cursor is on.
    public var cursorIndex: Int? {
        guard let c = cursor else { return nil }
        if numbered { return options.firstIndex { $0.n == c } }
        return options.indices.contains(c - 1) ? c - 1 : nil
    }

    public static func from(_ o: JSON) -> ScreenMenu? {
        guard o.object != nil else { return nil }
        let opts = o["options"].array.map {
            MenuOption(label: $0.str("label"), description: $0.str("description"), n: $0["n"].int, current: $0.flag("current"),
                       checked: $0.has("checked") ? $0.flag("checked") : nil, input: $0.flag("input"))
        }
        let scroll = o["scroll"]
        return ScreenMenu(id: o.str("id"), kind: o.str("kind"), title: o.str("title"), text: o.str("text"), options: opts,
                    cursor: o["cursor"].int, scrolls: scroll.flag("above") || scroll.flag("below"), multi: o.flag("multi"),
                    digits: o.flag("digits", true), body: o.str("body"), box: o.str("box"), footer: o.str("footer"), plan: o.str("plan"),
                    actions: o["actions"].array.map { a in MenuAction(label: a.str("label"), keys: a["keys"].array.compactMap(\.string)) },
                    blocks: o["blocks"].array.compactMap(PanelBlock.from),
                    tabs: o["tabs"].array.map { $0.str("label") }, nav: o.flag("nav"),
                    otherN: o["other"]["n"].int, submit: o["submit"].string)
    }

    /// Key steps that pick option `index` (0-based): its digit when the TUI takes digits, else arrows from the cursor and Enter.
    public func stepsToPick(_ index: Int) -> [JSON] {
        guard options.indices.contains(index) else { return [] }
        let opt = options[index]
        if digits, !scrolls, let n = opt.n, n < 10 { return [.string(String(n))] }
        let from = cursorIndex ?? 0
        let delta = index - from
        var steps: [JSON] = Array(repeating: .string(delta > 0 ? "Down" : "Up"), count: abs(delta))
        steps.append("Enter")
        return steps
    }
}

// MARK: usage / memory

public struct UsageWindow: Sendable, Hashable { public let name: String; public let pct: Double; public let resetsAt: Double; public let runsOutAt: Double? }
public struct UsageAccount: Sendable, Hashable, Identifiable {
    public var id: String { alias }
    public let alias: String, tool: String, label: String, plan: String, error: String
    public let windows: [UsageWindow]
    public let gone: Bool
    public static func from(_ o: JSON) -> UsageAccount {
        UsageAccount(alias: o.str("alias"), tool: o.str("tool"), label: o.str("label", o.str("alias")), plan: o.str("plan"),
                     error: o.str("error"),
                     windows: o["windows"].array.map { UsageWindow(name: $0.str("name"), pct: $0.num("pct"), resetsAt: $0.num("resets_at"),
                                                                     runsOutAt: $0["forecast"]["runs_out_at"].double) },
                     gone: o.flag("gone"))
    }
}

public struct DirEntry: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public let name: String, path: String, isGit: Bool
    public init(name: String, path: String, isGit: Bool) { self.name = name; self.path = path; self.isGit = isGit }
}

// MARK: cloud sessions (claude.ai/code, rpc/event `cloud_sessions`)

public struct CloudSession: Sendable, Hashable, Identifiable {
    public let id: String, alias: String, title: String, repo: String, branch: String
    public let state: String, question: String, detail: String, url: String
    public let lastAt: Double
    public let unread: Bool
    public var waiting: Bool { state == "waiting" }

    public static func from(_ o: JSON) -> CloudSession? {
        let id = o.str("id"); guard !id.isEmpty else { return nil }
        return CloudSession(id: id, alias: o.str("alias"), title: o.str("title", id), repo: o.str("repo"), branch: o.str("branch"),
                            state: o.str("state"), question: o.str("question"), detail: o.str("detail"), url: o.str("url"),
                            lastAt: o.num("last_at"), unread: o.flag("unread"))
    }
}
