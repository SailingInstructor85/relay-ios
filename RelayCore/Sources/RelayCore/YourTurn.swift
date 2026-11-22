import Foundation

/// „Dein Zug“: alles, was nur der Nutzer entscheiden oder beantworten kann, in einer Liste. Quellen sind die
/// wartenden Sitzungen (wie `Triage`), offene Rückfragen der Agenten (`Rueckfrage`), Freigaben des Desktops
/// (`SendReq`), Bestätigungen für Jarvis (`Confirm`) und wartende Cloud-Sitzungen. Entspricht „Needs you“ der
/// Android-App (TeamUi.kt): gemeinsam aufsteigend nach Zeit sortiert, das Älteste zuerst.
public enum YourTurn {
    public enum Kind: Int, Sendable, Equatable {
        case approval, confirm, question, session, cloud
    }

    /// Was ein Eintrag adressiert und womit die Karte antwortet.
    public enum Target: Sendable, Equatable {
        /// Wartende Sitzung: Sprung in den Chat (Schlüssel der Sitzung).
        case session(key: String)
        /// Rückfrage eines Agenten: Antwort direkt auf der Karte. `quick`: die Ein-Tipp-Antwort bei einer Empfehlung.
        case question(ref: String, agent: String, quick: String?)
        /// Freigabe: `newest` wird freigegeben, abgelehnt werden alle gleichen Anfragen (`all`, neueste zuerst).
        case approval(newest: String, all: [String])
        /// Bestätigung für Jarvis (`needs_confirmation`).
        case confirm(id: String)
        /// Cloud-Sitzung (claude.ai/code): öffnet die Adresse.
        case cloud(url: String)
    }

    public struct Item: Sendable, Equatable, Identifiable {
        public let id: String
        public let kind: Kind
        /// Seit wann der Eintrag wartet (Unix-Sekunden), 0 wenn unbekannt.
        public let since: Double
        public let title: String
        /// Zweite Zeile unter dem Titel („c1 · relay-ios“, „Angefragt von Jarvis“), kann leer sein.
        public let subtitle: String
        /// Die Frage oder der Wortlaut dessen, was freigegeben werden soll.
        public let text: String
        /// Kontext einer Rückfrage, sonst leer.
        public let context: String
        /// Empfehlung des Agenten, sonst leer.
        public let recommendation: String
        /// Freigaben: Ablauf (Unix-Sekunden), sonst 0.
        public let expiresAt: Double
        /// Freigaben: wie oft dasselbe angefragt wurde (1 = einmal).
        public let repeats: Int
        /// Sitzungen: Arbeitsordner für den Avatar, sonst leer.
        public let cwd: String
        public let target: Target

        public init(id: String, kind: Kind, since: Double, title: String, subtitle: String = "", text: String = "", context: String = "",
                    recommendation: String = "", expiresAt: Double = 0, repeats: Int = 1, cwd: String = "", target: Target) {
            self.id = id; self.kind = kind; self.since = since; self.title = title; self.subtitle = subtitle; self.text = text
            self.context = context; self.recommendation = recommendation; self.expiresAt = expiresAt; self.repeats = repeats
            self.cwd = cwd; self.target = target
        }
    }

    /// Die Liste für den Tab. `sessions`: die Sitzungen der Übersicht (ohne gerade geschlossene); Hintergrundläufe,
    /// Platzhalter und Sitzungen, die nicht warten, fallen hier heraus. `requests`: abgelaufene zählen nicht.
    public static func items(sessions: [Session], notices: [Notice], requests: [SendReq], confirms: [Confirm],
                             cloud: [CloudSession], now: Double) -> [Item] {
        var out: [Item] = []

        for g in SendRules.groups(requests.filter { $0.expiresAt > now && !$0.byPhone }) {
            guard let r = g.first else { continue }
            let stamps = g.map(\.createdAt).filter { $0 > 0 }
            out.append(Item(id: "approval:" + r.id, kind: .approval, since: stamps.min() ?? 0, title: SendRules.title(r),
                            subtitle: r.requestedBy.isEmpty ? "" : "Angefragt von \(r.requestedBy)", text: SendRules.body(r),
                            expiresAt: r.expiresAt, repeats: g.count, target: .approval(newest: r.id, all: g.map(\.id))))
        }

        for c in confirms {
            out.append(Item(id: "confirm:" + c.id, kind: .confirm, since: c.ts, title: confirmTitle, text: c.description,
                            target: .confirm(id: c.id)))
        }

        for n in notices where n.answer == nil {
            guard let q = Rueckfrage.question(n), q.wantsAnswer else { continue }
            out.append(Item(id: "question:" + n.ref, kind: .question, since: n.ts, title: Rueckfrage.title(q), text: q.question,
                            context: q.context, recommendation: q.recommendation,
                            target: .question(ref: n.ref, agent: q.agent, quick: Rueckfrage.quickAnswer(q))))
        }

        for s in sessions where s.waits && !s.background && !s.placeholder {
            out.append(Item(id: "session:" + s.key, kind: .session, since: s.lastActivity, title: s.name,
                            subtitle: [s.alias, s.folder].filter { !$0.isEmpty }.joined(separator: " · "), text: sessionText(s),
                            cwd: s.cwd, target: .session(key: s.key)))
        }

        for c in cloud where c.waiting {
            out.append(Item(id: "cloud:" + c.id, kind: .cloud, since: c.lastAt, title: c.title,
                            subtitle: c.repo.isEmpty ? "Cloud" : "Cloud · \(c.repo)", text: c.question.isEmpty ? c.detail : c.question,
                            target: .cloud(url: c.url)))
        }

        return out.sorted { a, b in
            if a.since != b.since { return a.since < b.since }
            if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
            return a.id < b.id
        }
    }

    /// Zahl für das Abzeichen am Tab.
    public static func count(sessions: [Session], notices: [Notice], requests: [SendReq], confirms: [Confirm],
                             cloud: [CloudSession], now: Double) -> Int {
        items(sessions: sessions, notices: notices, requests: requests, confirms: confirms, cloud: cloud, now: now).count
    }

    /// Worauf eine wartende Sitzung wartet: ihre Frage, sonst der fragende Schluss der letzten Antwort, sonst die
    /// letzte Nachricht.
    public static func sessionText(_ s: Session) -> String {
        if let q = s.question, !q.text.isEmpty { return q.text }
        if s.asksYou, !s.asksText.isEmpty { return s.asksText }
        return s.lastMessage
    }

    public static let confirmTitle = "Bestätigung von Jarvis"
    public static let empty = "Nichts wartet auf dich."

    /// „1 wartet auf dich“, „3 warten auf dich“, bei 0 der Leerzustand.
    public static func headline(_ count: Int) -> String {
        if count <= 0 { return empty }
        return count == 1 ? "1 wartet auf dich" : "\(count) warten auf dich"
    }

    /// Kurzwort für die Art eines Eintrags (Etikett auf der Karte, Vorlesen).
    public static func kindLabel(_ k: Kind) -> String {
        switch k {
        case .approval: return "Freigabe"
        case .confirm: return "Bestätigung"
        case .question: return "Rückfrage"
        case .session: return "Sitzung"
        case .cloud: return "Cloud"
        }
    }

    /// Hinweis unter einer Freigabe, die mehrfach angefragt wurde, sonst nil.
    public static func repeatsNote(_ repeats: Int) -> String? {
        repeats > 1 ? "\(repeats) gleiche Anfragen. Freigeben beantwortet nur die neueste." : nil
    }
}
