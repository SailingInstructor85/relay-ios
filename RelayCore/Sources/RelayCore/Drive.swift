import Foundation

/// Sprachmodus („Autofahrt“, 2026-11-07): offene Rückfragen der Agenten werden nacheinander vorgelesen (nur Frage und
/// Empfehlung), die Antwort kommt per Sprache, wird zur Kontrolle vorgelesen und geht erst nach „senden“ an
/// `rueckfrage`. Reine Logik: die App führt die Wirkungen (`DriveEffect`) der Reihe nach aus und meldet zurück, was sie
/// gehört hat oder ob das Senden geklappt hat.
public enum DriveCommand: Equatable, Sendable {
    /// „ja“: die Empfehlung annehmen (Antwort „ja“).
    case accept
    /// „nein“: ablehnen (Antwort „nein“).
    case decline
    /// Eine eigene Antwort in Worten.
    case answer(String)
    /// „senden“, „passt“: die vorgelesene Antwort abschicken.
    case send
    /// „nochmal“, „falsch“: die Antwort neu sprechen.
    case retry
    /// „wiederholen“, „wie bitte“: die Frage noch einmal vorlesen.
    case repeatQuestion
    /// „überspringen“, „später“: diese Rückfrage liegen lassen, weiter zur nächsten.
    case skip
    /// „stopp“, „beenden“: den Sprachmodus beenden.
    case stop
    /// Nichts verstanden (Stille).
    case silence
}

public enum DrivePhase: Equatable, Sendable {
    /// Noch nicht gestartet.
    case idle
    /// Die Frage ist vorgelesen, die App hört auf die Antwort.
    case answering
    /// Die Antwort ist zur Kontrolle vorgelesen, die App hört auf „senden“ oder „nochmal“.
    case confirming(String)
    /// Die Antwort ist unterwegs zum PC.
    case sending(String)
    /// Zweimal nichts gehört: wartet auf einen Tipp auf „Sprechen“.
    case paused
    /// Keine offene Rückfrage mehr: wartet auf neue (sie kommen über `enqueue`).
    case waiting
    /// Beendet.
    case stopped
}

public enum DriveEffect: Equatable, Sendable {
    /// Vorlesen und warten, bis es gesprochen ist.
    case say(String)
    /// Zuhören; das Ergebnis geht an `heard(_:)`.
    case listen
    /// Die Antwort an die Rückfrage `ref` schicken; das Ergebnis geht an `sent(error:)`.
    case send(ref: String, text: String)
}

/// Eine offene Rückfrage in der Warteschlange: Verweis auf den Hinweis und die Frage selbst.
public struct DriveItem: Equatable, Sendable {
    public let ref: String
    public let question: AgentQuestion
    public init(ref: String, question: AgentQuestion) { self.ref = ref; self.question = question }
}

public enum DriveText {
    static let acceptWords: Set<String> = ["ja", "jawohl", "jep", "jo", "okay", "ok", "einverstanden", "klar", "gerne", "gern", "yes"]
    static let declineWords: Set<String> = ["nein", "nö", "ne", "nee", "no"]
    static let sendWords: Set<String> = ["senden", "absenden", "schicken", "abschicken", "passt", "richtig", "genau", "korrekt", "stimmt", "ja", "jawohl", "okay", "ok", "send"]
    static let retryWords: Set<String> = ["nochmal", "noch mal", "falsch", "korrigieren", "ändern", "nein", "nee", "neu"]
    static let repeatWords: Set<String> = ["wie", "nochmal", "noch mal", "wiederholen", "wiederhole", "wie bitte", "nochmal vorlesen", "noch mal vorlesen", "frage wiederholen", "was", "bitte"]
    static let skipWords: Set<String> = ["überspringen", "später", "weiter", "nächste", "abbrechen", "skip"]
    static let stopWords: Set<String> = ["stopp", "stop", "beenden", "ende", "sprachmodus aus", "sprachmodus beenden", "aufhören", "tschüss", "tschüs"]

    /// Kleinbuchstaben, nur Buchstaben und Ziffern, ein Leerzeichen zwischen den Wörtern; ein „bitte“ am Ende fällt weg
    /// („ja bitte“, „senden bitte“).
    public static func norm(_ s: String) -> String {
        var w = SpeechText.words(s)
        if w.count > 1, w.last == "bitte" { w.removeLast() }
        if w.count > 1, w.first == "bitte" { w.removeFirst() }
        return w.joined(separator: " ")
    }

    /// Was eine kurze Äußerung beim Beantworten der Frage bedeutet. Längere Sätze sind immer eine eigene Antwort, auch
    /// wenn ein Steuerwort darin vorkommt („nein, erst nach dem Backup“ ist eine Antwort, kein schlichtes Nein).
    public static func forQuestion(_ heard: String) -> DriveCommand {
        let n = norm(heard)
        if n.isEmpty { return .silence }
        if stopWords.contains(n) { return .stop }
        if repeatWords.contains(n) { return .repeatQuestion }
        if skipWords.contains(n) { return .skip }
        if acceptWords.contains(n) || n == "ja gerne" || n == "mach das" || n == "machen" || n == "ja mach das" { return .accept }
        if declineWords.contains(n) || n == "nein danke" || n == "lieber nicht" { return .decline }
        return .answer(heard.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Was eine Äußerung nach dem Vorlesen der Antwort bedeutet. Alles andere als ein Steuerwort ersetzt die Antwort
    /// (so korrigiert man sich, ohne erst „nochmal“ zu sagen).
    public static func forConfirm(_ heard: String) -> DriveCommand {
        let n = norm(heard)
        if n.isEmpty { return .silence }
        if stopWords.contains(n) { return .stop }
        if sendWords.contains(n) || n == "ja senden" || n == "ja passt" { return .send }
        if retryWords.contains(n) || n == "nein nochmal" { return .retry }
        if skipWords.contains(n) { return .skip }
        if n == "wiederholen" || n == "wie" { return .repeatQuestion }
        return .answer(heard.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Die vorzulesende Frage: Nummer, Absender, Frage und Empfehlung, ohne Kontext. Beim ersten Mal der Hinweis, wie
    /// man antwortet.
    public static func prompt(_ q: AgentQuestion, index: Int, total: Int, hint: Bool) -> String {
        var s = total > 1 ? "Rückfrage \(index + 1) von \(total), von \(q.agent). " : "Rückfrage von \(q.agent). "
        s += ReadAloud.spoken(q)
        if hint {
            s += q.recommendation.isEmpty ? "\nSag deine Antwort." : "\nSag ja, nein oder deine Antwort."
        }
        return s
    }

    /// Die Antwort zur Kontrolle: „ja“ beim Annehmen mit der Empfehlung dazu, damit klar ist, was gilt.
    public static func confirmPrompt(_ answer: String, question q: AgentQuestion) -> String {
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if norm(a) == "ja", !q.recommendation.isEmpty, !acceptWords.contains(norm(q.recommendation)) {
            return "Ich antworte: ja, also \(ReadAloud.cleaned(q.recommendation)). Senden?"
        }
        return "Ich antworte: \(a). Senden oder nochmal?"
    }

    public static let sent = "Gesendet."
    public static let skipped = "Übersprungen."
    public static let nothingOpen = "Keine offene Rückfrage. Ich lese neue vor, sobald sie kommen."
    public static let allDone = "Alle Rückfragen sind erledigt. Ich lese neue vor, sobald sie kommen."
    public static let answeredElsewhere = "Diese Rückfrage ist schon beantwortet."
    public static let notHeard = "Ich habe nichts gehört."
    public static let paused = "Ich pausiere. Tippe auf Sprechen, wenn du antworten willst."
    public static let stopped = "Sprachmodus aus."
    public static func failed(_ why: String) -> String { "Nicht gesendet. \(why) Sag senden für einen neuen Versuch oder überspringen." }
}

/// Der Ablauf des Sprachmodus als Zustandsmaschine. Jede Methode gibt die nächsten Wirkungen zurück; die letzte ist
/// `listen` oder `send`, oder die Liste endet ohne beides (dann wartet die App auf `enqueue`, `resume` oder `stop`).
public struct DriveSession: Equatable, Sendable {
    public private(set) var phase: DrivePhase = .idle
    public private(set) var queue: [DriveItem] = []
    /// Erledigte oder übersprungene Rückfragen (kommen über `enqueue` nicht wieder).
    public private(set) var handled: Set<String> = []
    /// Wie viele Rückfragen in diesem Lauf schon vorgelesen wurden (für „Rückfrage 2 von 3“).
    public private(set) var asked = 0
    private var silent = 0
    private var hinted = false
    private var sendingRef: String?

    public init() {}

    public var current: DriveItem? { queue.first }
    public var isActive: Bool { phase != .idle && phase != .stopped }

    /// Startet mit den offenen Rückfragen (älteste zuerst).
    public mutating func start(_ items: [DriveItem]) -> [DriveEffect] {
        queue = items.filter { !handled.contains($0.ref) }
        asked = 0
        silent = 0
        if queue.isEmpty { phase = .waiting; return [.say(DriveText.nothingOpen)] }
        return ask()
    }

    /// Neue Rückfragen sind da. Liest sofort vor, wenn der Modus gerade wartet; sonst kommen sie in die Schlange.
    public mutating func enqueue(_ items: [DriveItem]) -> [DriveEffect] {
        guard isActive else { return [] }
        let known = Set(queue.map(\.ref)).union(handled)
        let fresh = items.filter { !known.contains($0.ref) }
        guard !fresh.isEmpty else { return [] }
        queue.append(contentsOf: fresh)
        if phase == .waiting { asked = 0; return ask() }
        return []
    }

    /// Eine Rückfrage wurde anderswo beantwortet (am PC, in der Mitteilung): sie fällt aus der Schlange. Ist es die
    /// gerade vorgelesene, geht es mit der nächsten weiter.
    public mutating func drop(ref: String) -> [DriveEffect] {
        handled.insert(ref)
        guard let i = queue.firstIndex(where: { $0.ref == ref }) else { return [] }
        queue.remove(at: i)
        guard i == 0, isActive, phase != .waiting, phase != .paused else { return [] }
        if case .sending = phase { return [] }
        return next(prefix: [.say(DriveText.answeredElsewhere)])
    }

    /// Was die App gehört hat (oder ein Knopf, siehe `command`).
    public mutating func heard(_ text: String) -> [DriveEffect] {
        switch phase {
        case .answering: return command(DriveText.forQuestion(text))
        case .confirming: return command(DriveText.forConfirm(text))
        default: return []
        }
    }

    /// Ein Befehl per Knopf oder Sprache.
    public mutating func command(_ c: DriveCommand) -> [DriveEffect] {
        if c == .stop { return stop() }
        if phase == .paused { return c == .silence ? [] : resume() }
        guard let item = current else { return [] }
        if c != .silence { silent = 0 }
        switch phase {
        case .answering:
            switch c {
            case .accept: return confirm("ja", item)
            case .decline: return confirm("nein", item)
            case .answer(let t): return confirm(t, item)
            case .repeatQuestion: return ask(again: true)
            case .skip: return skip()
            case .silence: return quiet(reask: true)
            case .send, .retry: return [.listen]
            case .stop: return stop()
            }
        case .confirming(let a):
            switch c {
            case .send, .accept: phase = .sending(a); sendingRef = item.ref; return [.send(ref: item.ref, text: a)]
            case .retry, .decline: phase = .answering; return [.say("Deine Antwort?"), .listen]
            case .answer(let t): return confirm(t, item)
            case .repeatQuestion: return ask(again: true)
            case .skip: return skip()
            case .silence: return quiet(reask: false)
            case .stop: return stop()
            }
        default:
            return []
        }
    }

    /// Das Senden ist fertig: nil = angekommen, sonst der Grund.
    public mutating func sent(error: String?) -> [DriveEffect] {
        guard case .sending(let a) = phase else { return [] }
        if let error {
            phase = .confirming(a)
            sendingRef = nil
            return [.say(DriveText.failed(error)), .listen]
        }
        if let ref = sendingRef {
            handled.insert(ref)
            queue.removeAll { $0.ref == ref }
        }
        sendingRef = nil
        return next(prefix: [.say(DriveText.sent)])
    }

    /// Nach einer Pause (Knopf „Sprechen“): die aktuelle Frage noch einmal.
    public mutating func resume() -> [DriveEffect] {
        guard phase == .paused || phase == .waiting else { return [] }
        silent = 0
        if current == nil { phase = .waiting; return [.say(DriveText.nothingOpen)] }
        return ask(again: true)
    }

    public mutating func stop() -> [DriveEffect] {
        let was = isActive
        phase = .stopped
        return was ? [.say(DriveText.stopped)] : []
    }

    // MARK: intern

    private mutating func ask(again: Bool = false) -> [DriveEffect] {
        guard let item = current else { phase = .waiting; return [.say(DriveText.allDone)] }
        if !again { asked += 1 }
        let total = asked - 1 + queue.count
        let text = DriveText.prompt(item.question, index: max(asked - 1, 0), total: total, hint: !hinted)
        hinted = true
        phase = .answering
        return [.say(text), .listen]
    }

    private mutating func confirm(_ answer: String, _ item: DriveItem) -> [DriveEffect] {
        phase = .confirming(answer)
        return [.say(DriveText.confirmPrompt(answer, question: item.question)), .listen]
    }

    private mutating func skip() -> [DriveEffect] {
        if let item = current { handled.insert(item.ref); queue.removeFirst() }
        return next(prefix: [.say(DriveText.skipped)])
    }

    private mutating func next(prefix: [DriveEffect]) -> [DriveEffect] {
        if current == nil { phase = .waiting; return prefix + [.say(DriveText.allDone)] }
        return prefix + ask()
    }

    /// Einmal still: nachfragen (beim Beantworten die Frage nochmal). Zweimal still: Pause, damit das Mikrofon nicht
    /// endlos offen bleibt.
    private mutating func quiet(reask: Bool) -> [DriveEffect] {
        silent += 1
        if silent >= 2 { phase = .paused; return [.say(DriveText.paused)] }
        if reask { return [.say(DriveText.notHeard)] + ask(again: true) }
        return [.say(DriveText.notHeard + " Senden oder nochmal?"), .listen]
    }
}

public enum DriveQueue {
    /// Die offenen Rückfragen aus den Hinweisen, älteste zuerst: nur echte Fragen (R…), noch ohne Antwort.
    public static func open(_ notices: [Notice]) -> [DriveItem] {
        notices.compactMap { n -> (Double, DriveItem)? in
            guard n.answer == nil, let q = Rueckfrage.question(n), q.wantsAnswer else { return nil }
            return (n.ts, DriveItem(ref: n.ref, question: q))
        }
        .sorted { $0.0 < $1.0 }
        .map { $0.1 }
    }
}

// MARK: Gespräch mit einer Sitzung

public enum TalkEffect: Equatable, Sendable {
    /// Vorlesen und warten, bis es gesprochen ist.
    case say(String)
    /// Zuhören; das Ergebnis geht an `heard(_:)`.
    case listen
    /// Den Text an die Sitzung schicken; das Ergebnis geht an `sent(error:)`.
    case send(String)
    /// Warten, bis die Sitzung fertig ist; die gekürzte Antwort geht an `replied(_:)`.
    case awaitReply
}

public enum TalkPhase: Equatable, Sendable {
    case idle
    /// Die App hört zu, was an die Sitzung gehen soll.
    case dictating
    /// Der Text ist zur Kontrolle vorgelesen: „senden“, „nochmal“ oder ein neuer Text.
    case confirming(String)
    case sending(String)
    /// Die Sitzung arbeitet, die App wartet auf ihre Antwort.
    case working
    case ended
}

/// Freihand-Gespräch mit einer Sitzung im Sprachmodus: sprechen, die Nachricht zur Kontrolle hören, „senden“, warten,
/// die Antwort gekürzt hören (kein Code, keine Pfade), danach hört die App wieder zu. Zweimal Stille oder „stopp“
/// beendet das Gespräch, der Sprachmodus wartet dann wieder auf Rückfragen.
public struct DriveTalk: Equatable, Sendable {
    public let key: String
    public let name: String
    public private(set) var phase: TalkPhase = .idle
    private var silent = 0

    public init(key: String, name: String) { self.key = key; self.name = name }

    public var isActive: Bool { phase != .idle && phase != .ended }

    public static func greeting(_ name: String) -> String { "Gespräch mit \(name). Was soll ich sagen?" }
    public static let again = "Was soll ich sagen?"
    public static let waiting = "Gesendet. Ich warte auf die Antwort."
    public static let ended = "Gespräch beendet. Ich lese wieder Rückfragen vor."
    public static func confirm(_ text: String, to name: String) -> String { "An \(name): \(text). Senden oder nochmal?" }
    public static func failed(_ why: String) -> String { "Nicht gesendet. \(why) Sag senden für einen neuen Versuch oder stopp." }
    public static func noReply(_ name: String) -> String { "\(name) arbeitet noch. Ich warte nicht länger, die Antwort steht später im Chat." }

    public mutating func start() -> [TalkEffect] {
        phase = .dictating
        silent = 0
        return [.say(Self.greeting(name)), .listen]
    }

    public mutating func heard(_ text: String) -> [TalkEffect] {
        switch phase {
        case .dictating:
            let n = DriveText.norm(text)
            if n.isEmpty { return quiet() }
            silent = 0
            if DriveText.stopWords.contains(n) || SpeechText.isStopPhrase(text) { return end() }
            return confirm(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case .confirming(let t):
            switch DriveText.forConfirm(text) {
            case .send: phase = .sending(t); silent = 0; return [.send(t)]
            case .retry: phase = .dictating; silent = 0; return [.say(Self.again), .listen]
            case .answer(let n): silent = 0; return confirm(n)
            case .stop, .skip: return end()
            case .silence: return quiet()
            default: return [.listen]
            }
        default:
            return []
        }
    }

    /// Knöpfe: Senden, Nochmal, Beenden.
    public mutating func command(_ c: DriveCommand) -> [TalkEffect] {
        switch (phase, c) {
        case (.confirming(let t), .send): phase = .sending(t); return [.send(t)]
        case (.confirming, .retry): phase = .dictating; return [.say(Self.again), .listen]
        case (_, .stop): return end()
        default: return []
        }
    }

    public mutating func sent(error: String?) -> [TalkEffect] {
        guard case .sending(let t) = phase else { return [] }
        if let error { phase = .confirming(t); return [.say(Self.failed(error)), .listen] }
        phase = .working
        return [.say(Self.waiting), .awaitReply]
    }

    /// Die Antwort der Sitzung (schon gekürzt), oder nil, wenn sie zu lange gebraucht hat.
    public mutating func replied(_ spoken: String?) -> [TalkEffect] {
        guard phase == .working else { return [] }
        guard let spoken, !spoken.isEmpty else {
            phase = .ended
            return [.say(Self.noReply(name))]
        }
        phase = .dictating
        silent = 0
        return [.say(spoken), .listen]
    }

    public mutating func end() -> [TalkEffect] {
        let was = isActive
        phase = .ended
        return was ? [.say(Self.ended)] : []
    }

    private mutating func confirm(_ t: String) -> [TalkEffect] {
        phase = .confirming(t)
        return [.say(Self.confirm(t, to: name)), .listen]
    }

    private mutating func quiet() -> [TalkEffect] {
        silent += 1
        if silent >= 2 { return end() }
        return [.say(DriveText.notHeard + (phase == .dictating ? " " + Self.again : " Senden oder nochmal?")), .listen]
    }

    /// Was von der Antwort vorgelesen wird: die Kurzfassung des Gateways, sonst die ersten Sätze der letzten Nachricht
    /// ohne Code und Pfade; wartet die Sitzung auf eine Auswahl, kommt die Frage mit den Optionen dazu.
    public static func spokenReply(summary: String?, lastMessage: String, question: Question?) -> String {
        var parts: [String] = []
        let s = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = s.isEmpty ? SpeechText.brief(ReadAloud.cleaned(lastMessage), max: 300) : s
        if !base.isEmpty { parts.append(base) }
        if let question { parts.append(ReadAloud.spoken(question: question)) }
        return parts.joined(separator: "\n")
    }
}
