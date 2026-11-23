import Foundation

/// What a session event is about, for the notification decision.
public enum AlertKind: Sendable { case ready, needsInput, ended }

/// What a notification does: rings (banner and sound), lands silently in the list, or does not appear at all.
public enum NotifyAlert: Sendable, Equatable { case popup, silent, none }

/// The notification settings as the policy needs them (UserDefaults on the phone).
public struct NotifyPrefs: Sendable, Equatable {
    /// "sound" | "silent" | "off"
    public var ready = "sound"
    /// "popup" | "silent"
    public var input = "popup"
    /// "tasks" | "same" | "silent"
    public var auto = "tasks"
    public var quietAtDesk = true
    public var quietHours = false
    public var quietFrom = 22 * 60
    public var quietTo = 7 * 60
    public init() {}
    public init(ready: String = "sound", input: String = "popup", auto: String = "tasks", quietAtDesk: Bool = true,
                quietHours: Bool = false, quietFrom: Int = 22 * 60, quietTo: Int = 7 * 60) {
        self.ready = ready; self.input = input; self.auto = auto; self.quietAtDesk = quietAtDesk
        self.quietHours = quietHours; self.quietFrom = quietFrom; self.quietTo = quietTo
    }
}

/// The parts of a `session_state` event the policy looks at.
public struct StateInfo: Sendable, Equatable {
    public var quiet = false, desk = false, asks = false
    public var origin = ""
    public var tasks = 0
    public init() {}
    public init(quiet: Bool = false, desk: Bool = false, asks: Bool = false, origin: String = "", tasks: Int = 0) {
        self.quiet = quiet; self.desk = desk; self.asks = asks; self.origin = origin; self.tasks = tasks
    }
    public static func from(_ ev: JSON) -> StateInfo {
        StateInfo(quiet: ev.flag("quiet"), desk: ev.flag("desk"), asks: ev.flag("asks"), origin: ev.str("origin"), tasks: ev["tasks"].int ?? 0)
    }
}

/// Port of the Android app's NotifyPolicy / QuietHours (Digest.kt).
public enum NotifyPolicy {
    /// Order: muted -> none; a quiet ready -> none; base from the setting; at the desk -> silent; an agent's own turn
    /// -> silent; quiet hours -> silent (a question always rings).
    public static func alert(_ kind: AlertKind, _ p: NotifyPrefs, muted: Bool, ev: StateInfo? = nil, minuteOfDay: Int? = nil) -> NotifyAlert {
        let base: NotifyAlert
        if muted { base = .none }
        else if kind == .ready && ev?.quiet == true { base = .none }
        else if kind == .ready { base = p.ready == "off" ? .none : (p.ready == "silent" ? .silent : .popup) }
        else if kind == .needsInput { base = p.input == "silent" ? .silent : .popup }
        else { base = .popup }
        guard base == .popup else { return base }
        if let ev, p.quietAtDesk, ev.desk { return .silent }
        if kind == .ready, let ev, quietAuto(p.auto, ev) { return .silent }
        // a question (waiting for input, or a reply that asks) always rings
        let question = kind == .needsInput || ev?.asks == true
        if !question, let m = minuteOfDay, QuietHours.active(p, m) { return .silent }
        return base
    }

    /// A turn the agent started itself is silent: "tasks" while background tasks still run, "silent" always, "same" never.
    /// A reply that asks something still rings.
    public static func quietAuto(_ mode: String, _ ev: StateInfo) -> Bool {
        guard ev.origin == "auto", !ev.asks else { return false }
        switch mode {
        case "same": return false
        case "silent": return true
        default: return ev.tasks > 0
        }
    }

    /// Only a turn the user started clears the notifications when the session goes busy.
    public static func clearsOnBusy(origin: String?) -> Bool { origin.map { $0 == "user" } ?? false }
}

public enum QuietHours {
    public static func active(_ p: NotifyPrefs, _ minuteOfDay: Int) -> Bool {
        p.quietHours && within(p.quietFrom, p.quietTo, minuteOfDay)
    }
    /// [from, to) in minutes of the day, across midnight when from > to; from == to is never.
    public static func within(_ from: Int, _ to: Int, _ m: Int) -> Bool {
        if from == to { return false }
        if from < to { return m >= from && m < to }
        return m >= from || m < to
    }
    public static func label(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    public static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// A notice from the Desktop as the phone keeps it.
public struct Notice: Sendable, Equatable, Identifiable {
    public var id: String { ref }
    public let ref: String
    public let ts: Double
    public let title: String, text: String, source: String
    public let tag: String?, handoff: String?, member: String?
    /// The user's answer to an agent's question (`Rueckfrage`), once it reached the Desktop.
    public var answer: String?
    public init(ref: String, ts: Double, title: String, text: String, source: String, tag: String? = nil, handoff: String? = nil,
                member: String? = nil, answer: String? = nil) {
        self.ref = ref; self.ts = ts; self.title = title; self.text = text; self.source = source
        self.tag = tag; self.handoff = handoff; self.member = member; self.answer = answer
    }

    public func json() -> JSON {
        JSON.obj(["ref": .string(ref), "ts": .number(ts), "title": .string(title), "text": .string(text), "source": .string(source),
                  "tag": tag.map { .string($0) }, "handoff": handoff.map { .string($0) }, "member": member.map { .string($0) },
                  "answer": answer.map { .string($0) }])
    }
    public static func from(json o: JSON) -> Notice? {
        let ref = o.str("ref")
        guard !ref.isEmpty else { return nil }
        func opt(_ k: String) -> String? { let s = o.str(k); return s.isEmpty ? nil : s }
        return Notice(ref: ref, ts: o.num("ts"), title: o.str("title"), text: o.str("text"), source: o.str("source"),
                      tag: opt("tag"), handoff: opt("handoff"), member: opt("member"), answer: opt("answer"))
    }
    /// From a `notice` event: the gateway's seq names it.
    public static func from(event ev: JSON, now: Double) -> Notice {
        let seq = ev["seq"].int ?? 0
        func opt(_ k: String) -> String? { let s = ev.str(k); return s.isEmpty ? nil : s }
        return Notice(ref: seq > 0 ? "s\(seq)" : "l\(Int(now * 1000))", ts: ev.num("ts") > 0 ? ev.num("ts") : now,
                      title: ev.str("title"), text: ev.str("text"), source: ev.str("source"),
                      tag: opt("tag"), handoff: opt("handoff"), member: opt("member"))
    }
}

public enum NoticeLogic {
    public static let keep = 100
    public static let keepDays = 14
    public static let maxAge: Double = 86_400

    /// Shown live and when replayed within 24 h (no time = show).
    public static func show(ts: Double, now: Double) -> Bool { ts <= 0 || now - ts < maxAge }

    /// The notification slot: a tag maps to one, without a tag each notice has its own.
    public static func slot(tag: String?, seq: Int) -> String {
        if let t = tag, !t.trimmingCharacters(in: .whitespaces).isEmpty { return "notice:\(t)" }
        return "notice#\(seq)"
    }

    /// `n` into the kept list: newest first, each ref once, the last 14 days, at most 100. A notice that comes again
    /// (replay) keeps the answer already given.
    public static func merge(_ list: [Notice], _ n: Notice, now: Double) -> [Notice] {
        var n = n
        if n.answer == nil, let old = list.first(where: { $0.ref == n.ref }) { n.answer = old.answer }
        return ([n] + list.filter { $0.ref != n.ref })
            .filter { now - $0.ts < Double(keepDays) * 86_400 }
            .sorted { $0.ts > $1.ts }
            .prefix(keep).map { $0 }
    }

    /// A line of the text and its web links (each a button; the line shows without them).
    public struct Line: Sendable, Equatable { public let text: String; public let links: [String] }

    public static func lines(_ text: String) -> [Line] {
        let multi = Rx.make("[ \\t]{2,}")
        let trailPunct = Rx.make("\\s+([,;:.])\\s*$")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").map { raw in
            var shown = raw
            var links: [String] = []
            for l in Links.extract(raw) {
                guard let url = web(l.target) else { continue }
                links.append(url)
                if l.label != l.target { shown = shown.replacingOccurrences(of: "[\(l.label)](\(l.target))", with: l.label) }
                else { shown = shown.replacingOccurrences(of: l.target, with: "") }
            }
            shown = multi.stringByReplacingMatches(in: shown, range: NSRange(location: 0, length: (shown as NSString).length), withTemplate: " ")
            shown = trailPunct.stringByReplacingMatches(in: shown, range: NSRange(location: 0, length: (shown as NSString).length), withTemplate: "")
            shown = shown.trimmingCharacters(in: .whitespaces)
            if shown.isEmpty, let f = links.first { shown = host(f) }
            return Line(text: shown, links: links)
        }
    }

    /// An http(s) link as it opens ("www.x.de" -> https), nil for anything else (files, mail).
    public static func web(_ target: String) -> String? {
        let t = target.lowercased()
        if t.hasPrefix("https://") || t.hasPrefix("http://") { return target }
        if t.hasPrefix("www.") { return "https://" + target }
        return nil
    }

    /// "amazon.de" for "https://www.amazon.de/dp/...".
    public static func host(_ url: String) -> String {
        var s = url
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        for sep in ["/", "?", ":"] { if let r = s.range(of: sep) { s = String(s[..<r.lowerBound]) } }
        return s.hasPrefix("www.") ? String(s.dropFirst(4)) : s
    }

    /// Where the notice's own button leads. Only places the iPhone app has.
    public enum Goto: Sendable, Equatable { case accounts, sessions, jarvis, none }

    public static func goto(_ n: Notice) -> Goto {
        guard let t = n.tag else { return .none }
        if t.hasPrefix("quota-") { return .accounts }
        if t == "hibernate" || t == "restore" || t == "digest" { return .sessions }
        if t == "jarvis" { return .jarvis }
        return .none
    }

    public static func encode(_ list: [Notice]) -> String { JSON.array(list.map { $0.json() }).serialized() }
    public static func decode(_ text: String) -> [Notice] { JSON.parse(text)?.array.compactMap { Notice.from(json: $0) } ?? [] }
}

/// A question an agent on the Desktop asks while the user is away (`~/.agents/bin/rueckfrage neu`), or a report
/// (`rueckfrage meldung`). Both reach the phone as a `notice` (`notifyd phone notify`) whose tag names them:
/// `rueckfrage:<agent>:R<n>` for a question, `meldung:<agent>:M<n>` for a report. The notice text carries the question
/// and, each on its own line, "Kontext: …" and "Empfehlung: …".
public struct AgentQuestion: Sendable, Equatable {
    public let agent: String, id: String
    public let question: String, context: String, recommendation: String
    public init(agent: String, id: String, question: String, context: String = "", recommendation: String = "") {
        self.agent = agent; self.id = id; self.question = question; self.context = context; self.recommendation = recommendation
    }
    /// A question wants an answer; a report (M…) is only shown.
    public var wantsAnswer: Bool { id.hasPrefix("R") }
}

public enum Rueckfrage {
    /// The inbox app name the answer travels under (`inbox_put`, kind `notification`, app `rueckfrage`).
    public static let app = "rueckfrage"

    /// "rueckfrage:relay-ios:R1" -> (relay-ios, R1); "meldung:relay-ios:M2" -> (relay-ios, M2); anything else nil.
    public static func parse(tag: String?) -> (agent: String, id: String)? {
        guard let tag else { return nil }
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, !parts[1].isEmpty else { return nil }
        let id = parts[2].uppercased()
        let kind = parts[0].lowercased()
        let numbered = id.count >= 2 && id.dropFirst().allSatisfy(\.isNumber)
        guard numbered else { return nil }
        if kind == "rueckfrage" && id.hasPrefix("R") { return (parts[1], id) }
        if kind == "meldung" && id.hasPrefix("M") { return (parts[1], id) }
        return nil
    }

    /// The question of a notice, when it is one (its tag says so), with context and recommendation split off the text.
    public static func question(_ n: Notice) -> AgentQuestion? {
        guard let parsed = parse(tag: n.tag) else { return nil }
        var q: [String] = [], ctx: [String] = [], rec: [String] = []
        var current = 0  // 0 question, 1 context, 2 recommendation
        for raw in n.text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let r = label(line, "Kontext") { current = 1; ctx.append(r); continue }
            if let r = label(line, "Empfehlung") { current = 2; rec.append(r); continue }
            switch current { case 1: ctx.append(line); case 2: rec.append(line); default: q.append(line) }
        }
        func joined(_ l: [String]) -> String { l.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
        var question = joined(q)
        if question.isEmpty { question = n.title }
        return AgentQuestion(agent: parsed.agent, id: parsed.id, question: question, context: joined(ctx), recommendation: joined(rec))
    }

    private static func label(_ line: String, _ name: String) -> String? {
        for prefix in ["**\(name):**", "\(name):"] where line.lowercased().hasPrefix(prefix.lowercased()) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// "Rückfrage R1 von relay-ios" / "Meldung M2 von relay-ios" (when the notice has no title of its own).
    public static func title(_ q: AgentQuestion) -> String {
        (q.wantsAnswer ? "Rückfrage " : "Meldung ") + q.id + " von " + q.agent
    }

    /// The one-tap answer when the agent made a recommendation ("ja" accepts it), else nil.
    public static func quickAnswer(_ q: AgentQuestion) -> String? {
        q.wantsAnswer && !q.recommendation.isEmpty ? "ja" : nil
    }

    /// The notification category: with a text field to answer, plus "Ja" when there is a recommendation.
    public static func category(_ q: AgentQuestion) -> String? {
        guard q.wantsAnswer else { return nil }
        return quickAnswer(q) != nil ? "rueckfrage-ja" : "rueckfrage"
    }

    /// The inbox item that carries the answer back (`inbox_put`, kind `notification`): the Desktop's `rueckfrage warten`
    /// reads it through `notifyd phone inbox --kind notification --app rueckfrage` (or the inbox's JSONL files).
    public static func answerItem(agent: String, id: String, answer: String, now: Double) -> JSON {
        .object(["id": .string("rueckfrage|\(agent)|\(id)|\(Int(now * 1000))"), "ts": .number(now),
                 "app": .string(app), "app_label": .string("Rückfrage"), "title": .string("\(agent) \(id)"),
                 "text": .string(answer), "conversation": .string(agent), "has_reply": .bool(false)])
    }

    // MARK: Schließen auf allen Geräten (PROTOCOL.md des Gateways, „Rückfragen“, 2026-11-24)
    //
    // Wahr ist der Stand am PC (die Dateien des Skripts `rueckfrage`). Die App spiegelt ihn: das Ereignis
    // `rueckfrage_resolved {tag, answer}` schließt eine Rückfrage sofort, der Abgleich `rueckfrage_status` nach jedem
    // Verbinden alles, was ein Ereignis verpasst hat.

    /// Die Antwort, mit der eine Rückfrage ohne Bearbeiten geschlossen wird (Knopf „Erledigt“). Sie geht denselben Weg
    /// wie jede Antwort, der Agent am PC bekommt sie als Antwort.
    public static let dismissed = "(verworfen)"
    /// Vermerk an einer Rückfrage, die der PC nicht mehr kennt (Abgleich: `unbekannt`), dort wartet niemand mehr.
    public static let gone = "(nicht mehr offen)"

    /// Der Tag einer Frage in der Schreibweise des Gateways (`rueckfrage:<agent>:R<n>`, Nummer groß), nil für Meldungen
    /// und alles andere. Tags werden nur in dieser Form verglichen und verschickt.
    public static func canonical(tag: String?) -> String? {
        guard let p = parse(tag: tag?.trimmingCharacters(in: .whitespacesAndNewlines)), p.id.hasPrefix("R") else { return nil }
        return "rueckfrage:\(p.agent):\(p.id)"
    }

    /// Eine offene Rückfrage: ein Hinweis mit dem Tag einer Frage (R…) und noch ohne Antwort.
    public static func isOpen(_ n: Notice) -> Bool {
        n.answer == nil && (parse(tag: n.tag)?.id.hasPrefix("R") ?? false)
    }

    /// Setzt die Antwort an jeder offenen Rückfrage mit diesem Tag (mehrere Hinweise können denselben Tag tragen).
    /// Eine schon gesetzte Antwort bleibt. Ohne Antworttext gilt die Rückfrage als verworfen. `changed`: die Kennungen
    /// der Hinweise, die dadurch zugingen.
    public static func resolve(_ list: [Notice], tag: String, answer: String) -> (list: [Notice], changed: [String]) {
        guard let tag = canonical(tag: tag) else { return (list, []) }
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = list
        var changed: [String] = []
        for i in out.indices where isOpen(out[i]) && canonical(tag: out[i].tag) == tag {
            out[i].answer = text.isEmpty ? dismissed : text
            changed.append(out[i].ref)
        }
        return (out, changed)
    }

    /// Die Tags der offenen Rückfragen für `rueckfrage_status`, jeder einmal, höchstens 500 (Grenze des Gateways).
    public static func openTags(_ list: [Notice]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for n in list where isOpen(n) {
            guard let t = canonical(tag: n.tag), seen.insert(t).inserted else { continue }
            out.append(t)
        }
        return Array(out.prefix(500))
    }

    /// Was der Abgleich schließt: aus der Antwort von `rueckfrage_status` alles mit `beantwortet` (mit der Antwort vom
    /// PC) oder `unbekannt`. `offen` und unbekannte Werte bleiben offen. Eine Antwort ohne `items` (älteres Gateway,
    /// Fehler) schließt nichts.
    public static func closures(status r: JSON) -> [(tag: String, answer: String)] {
        r["items"].array.compactMap { it -> (tag: String, answer: String)? in
            let tag = it.str("tag")
            guard !tag.isEmpty else { return nil }
            switch it.str("status") {
            case "beantwortet":
                let a = it.str("answer").trimmingCharacters(in: .whitespacesAndNewlines)
                return (tag, a.isEmpty ? "(am PC beantwortet)" : a)
            case "unbekannt": return (tag, gone)
            default: return nil
            }
        }
    }

    /// Der ganze Abgleich auf die Liste angewandt.
    public static func reconcile(_ list: [Notice], status r: JSON) -> (list: [Notice], changed: [String]) {
        var out = list
        var changed: [String] = []
        for c in closures(status: r) {
            let step = resolve(out, tag: c.tag, answer: c.answer)
            out = step.list
            changed += step.changed
        }
        return (out, changed)
    }

    /// Zeile an einer geschlossenen Rückfrage: „Beantwortet: ja“, „Verworfen (ohne Antwort geschlossen)“.
    public static func answeredLabel(_ answer: String) -> String {
        switch answer {
        case dismissed: return "Verworfen (ohne Antwort geschlossen)"
        case gone: return "Am PC nicht mehr offen"
        default: return "Beantwortet: \(answer)"
        }
    }

    /// Hinweis, wenn eine Antwort auf eine schon geschlossene Rückfrage geschickt werden soll: keine Fehlermeldung,
    /// sondern was schon gilt.
    public static func alreadyAnswered(_ answer: String) -> String {
        switch answer {
        case dismissed: return "Schon erledigt: Die Rückfrage wurde ohne Antwort geschlossen."
        case gone: return "Schon erledigt: Am PC ist die Rückfrage nicht mehr offen."
        default: return "Schon beantwortet: \(answer)"
        }
    }

    public static let dismissLabel = "Erledigt"
    public static let dismissTitle = "Rückfrage ohne Antwort schließen?"
    public static let dismissConfirm = "Ohne Antwort schließen"
    public static func dismissNote(agent: String) -> String {
        "Sie verschwindet auf allen Geräten. \(agent) bekommt „\(dismissed)“ als Antwort."
    }
}

/// Das Blatt „Rückfrage jetzt“ beim Öffnen der App (2026-11-24): Sind Rückfragen offen, zeigt es die älteste mit vollem
/// Wortlaut, Kontext und Empfehlung. „Später“ blendet es aus, bis eine neuere Rückfrage dazukommt. Die Karten in
/// „Dein Zug“ bleiben davon unberührt.
public enum QuestionPrompt {
    /// Einstellungsschlüssel: Zeitstempel der neuesten Rückfrage, die beim letzten „Später“ offen war.
    public static let laterKey = "questionPromptLaterUpTo"
    public static let title = "Rückfrage jetzt"
    public static let laterLabel = "Später"

    /// Die offenen Rückfragen, älteste zuerst.
    public static func open(_ notices: [Notice]) -> [Notice] {
        notices.filter(Rueckfrage.isOpen).sorted { ($0.ts, $0.ref) < ($1.ts, $1.ref) }
    }

    /// Was das Blatt beim Öffnen zeigt: die älteste offene Rückfrage, wenn seit dem letzten „Später“ (`laterUpTo`)
    /// eine neuere dazugekommen ist oder nie „Später“ getippt wurde. Sonst nil, das Blatt bleibt zu.
    public static func offer(_ notices: [Notice], laterUpTo: Double) -> Notice? {
        let list = open(notices)
        guard list.contains(where: { $0.ts > laterUpTo }) else { return nil }
        return list.first
    }

    /// Der Wert, den „Später“ merkt: der Zeitstempel der neuesten offenen Rückfrage (nie kleiner als der bisherige).
    public static func later(_ notices: [Notice], previous: Double) -> Double {
        max(previous, open(notices).map(\.ts).max() ?? 0)
    }

    /// „1 offene Rückfrage“, „3 offene Rückfragen, die älteste zuerst“.
    public static func countLabel(_ n: Int) -> String {
        n == 1 ? "1 offene Rückfrage" : "\(n) offene Rückfragen, die älteste zuerst"
    }
}

/// A `send_request` event: the Desktop asks for an approval (mail, invite, post, order, payment).
public struct SendReq: Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String, executor: String, app: String, conversation: String
    public var text: String, summary: String, requestedBy: String
    public var expiresAt: Double, createdAt: Double

    public var byPhone: Bool { executor == "phone" }

    public static func from(event o: JSON, now: Double = 0) -> SendReq? {
        let id = o.str("request_id")
        guard !id.isEmpty else { return nil }
        var created = o.num("created_at")
        if created <= 0 { created = o.num("ts", now) }
        return SendReq(id: id, kind: o.str("kind", "message"), executor: o.str("executor", "desktop"), app: o.str("app"),
                       conversation: o.str("conversation"), text: o.str("text"), summary: o.str("summary"),
                       requestedBy: o.str("requested_by"), expiresAt: o.num("expires_at"), createdAt: created)
    }

    public func json() -> JSON {
        .object(["request_id": .string(id), "kind": .string(kind), "executor": .string(executor), "app": .string(app),
                 "conversation": .string(conversation), "text": .string(text), "summary": .string(summary),
                 "requested_by": .string(requestedBy), "expires_at": .number(expiresAt), "created_at": .number(createdAt)])
    }
}

public enum SendRules {
    /// Show a request only while the iPhone can decide it (a desktop executor), it is unexpired, not already shown
    /// and not already answered. `message` requests (reply via WhatsApp etc.) only work on the Android phone.
    public static func accept(now: Double, _ r: SendReq, pending: Set<String>, handled: Set<String>) -> Bool {
        !r.byPhone && r.expiresAt > now && !pending.contains(r.id) && !handled.contains(r.id)
    }

    public static func title(_ r: SendReq) -> String {
        switch r.kind {
        case "mail": return "E-Mail freigeben?"
        case "invite": return "Einladung freigeben?"
        case "post": return "Beitrag freigeben?"
        case "order": return "Bestellung freigeben?"
        case "payment": return "Zahlung freigeben?"
        default: return "\(r.kind) freigeben?"
        }
    }

    public static func body(_ r: SendReq) -> String {
        var seen: [String] = []
        for s in [r.summary, r.text] where !s.isEmpty && !seen.contains(s) { seen.append(s) }
        return seen.joined(separator: "\n\n")
    }

    /// One line for the strip.
    public static func headline(_ r: SendReq) -> String { r.summary.isEmpty ? title(r) : r.summary }

    /// Requests that ask the same thing again, newest first in each group; only the newest gets "Freigeben".
    public static func groups(_ reqs: [SendReq]) -> [[SendReq]] {
        var order: [String] = []
        var by: [String: [SendReq]] = [:]
        for r in reqs {
            let k = [r.kind, r.executor, r.app, r.conversation, r.text, r.summary, r.requestedBy].joined(separator: "\u{1}")
            if by[k] == nil { order.append(k) }
            by[k, default: []].append(r)
        }
        func stamp(_ r: SendReq) -> Double { r.createdAt > 0 ? r.createdAt : r.expiresAt }
        return order.compactMap { by[$0] }
            .map { $0.sorted { stamp($0) > stamp($1) } }
            .sorted { stamp($0[0]) > stamp($1[0]) }
    }

    /// Text of the strip: one request by its summary, several as a count.
    public static func stripText(groups: Int, confirms: Int, first: String?) -> String {
        let n = groups + confirms
        if n == 0 { return "" }
        if n == 1, let f = first, !f.isEmpty { return "Freigeben? \(f)" }
        return "\(n) Freigaben warten"
    }
}

/// A Jarvis confirmation (`needs_confirmation`).
public struct Confirm: Sendable, Equatable, Identifiable {
    public let id: String, description: String, ts: Double
    public init(id: String, description: String, ts: Double = 0) { self.id = id; self.description = description; self.ts = ts }
}

public enum ConfirmRules {
    /// Replayed confirmations count only when younger than 30 minutes (ts 0 = unknown, show).
    public static func fresh(ts: Double, now: Double) -> Bool { ts <= 0 || now - ts < 30 * 60 }
}
