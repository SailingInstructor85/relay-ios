import XCTest
@testable import RelayCore

final class SpeechTests: XCTestCase {
    func testStopPhrase() {
        XCTAssertTrue(SpeechText.isStopPhrase("Danke"))
        XCTAssertTrue(SpeechText.isStopPhrase("ok, danke dir"))
        XCTAssertTrue(SpeechText.isStopPhrase("Tschüss!"))
        XCTAssertFalse(SpeechText.isStopPhrase("danke das war sehr hilfreich heute"))
        XCTAssertFalse(SpeechText.isStopPhrase("was wartet auf mich"))
        XCTAssertFalse(SpeechText.isStopPhrase(""))
    }

    func testBrief() {
        let t = "Fertig. Ich habe die Tests angepasst. Danach lief alles grün. Noch ein langer dritter Satz folgt hier."
        XCTAssertEqual(SpeechText.brief(t, max: 70), "Fertig. Ich habe die Tests angepasst. Danach lief alles grün.")
        XCTAssertEqual(SpeechText.strip("**Hallo** [Link](http://x) ```code``` Ende"), "Hallo Link Ende")
    }

    func testSentences() {
        var s = SentenceSplitter()
        var out = s.add("Das ist der erste Satz. Am 4. Oktober ")
        XCTAssertEqual(out, ["Das ist der erste Satz."])
        out = s.add("gibt es mehr. Rest")
        XCTAssertEqual(out, ["Am 4. Oktober gibt es mehr."])
        XCTAssertEqual(s.end(), "Rest")
    }

    func testDetect() {
        XCTAssertEqual(Voices.detect("Die Sitzung ist fertig und wartet auf dich"), "de")
        XCTAssertEqual(Voices.detect("The session is done and waiting for you"), "en")
        XCTAssertNil(Voices.detect("Xyzzy"))
        XCTAssertEqual(Voices.langFor("Xyzzy", setting: "auto", fallback: "en"), "en")
        XCTAssertEqual(Voices.langFor("the and is", setting: "de"), "de")
        XCTAssertEqual(Voices.recognitionLocale(setting: "auto", preferred: ["en-DE"]), "en-US")
        XCTAssertEqual(Voices.recognitionLocale(setting: "auto", preferred: ["fr-FR"]), "de-DE")
    }

    func testBiasing() {
        let b = SpeechVocab.biasing(["work/api-merge", "Relay", "ab", "relay"])
        XCTAssertEqual(b, ["work", "api", "merge", "Relay"])
    }

    func testPickAndCorrect() {
        XCTAssertEqual(SpeechVocab.pick(["hallo welt", "hallo Relay"], conf: [0.5, 0.45], terms: ["Relay"]), "hallo Relay")
        XCTAssertEqual(SpeechVocab.pick(["a b", "c d"], conf: [], terms: []), "a b")
        // an alternative that covers only part of what was said never wins, however confident
        XCTAssertEqual(SpeechVocab.pick(["um Leuten zu zeigen, was wir hier machen", "machen"], conf: [0.4, 0.95], terms: []),
                       "um Leuten zu zeigen, was wir hier machen")
        let c = [(heard: "rely", meant: "Relay"), (heard: "ge it hub", meant: "GitHub"), (heard: "ge it", meant: "X")]
        XCTAssertEqual(SpeechVocab.correct("Rely und ge it hub, relyx", c), "Relay und GitHub, relyx")
    }

    func testHistory() {
        let t = [JarvisTurn(q: "Was wartet?", a: "Nichts", voice: false), JarvisTurn(q: "offen", a: "", voice: true)]
        let back = JarvisHistory.decode(JarvisHistory.encode(t)!)
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(JarvisHistory.search(back, query: "nichts wartet").count, 1)
        XCTAssertTrue(VoiceMode.isLive("live"))
    }

    func testDictationRestart() {
        let said = "Ich möchte dir zeigen, was wir hier"
        // the recogniser started over after a pause: only the words after it come back
        XCTAssertTrue(DictationText.restarted(previous: said, current: "machen"))
        XCTAssertTrue(DictationText.restarted(previous: said, current: "Machen, um"))
        // revisions keep the length or the beginning
        XCTAssertFalse(DictationText.restarted(previous: said, current: "Ich möchte dir zeigen, was wir hier machen."))
        XCTAssertFalse(DictationText.restarted(previous: said, current: "Ich möchte"))
        XCTAssertFalse(DictationText.restarted(previous: said, current: "Ich, möchte dir"))
        // too little before to tell, or nothing new
        XCTAssertFalse(DictationText.restarted(previous: "Hallo", current: "Du"))
        XCTAssertFalse(DictationText.restarted(previous: said, current: ""))
        XCTAssertEqual(DictationText.join("", "b"), "b")
        XCTAssertEqual(DictationText.join("a ", " b"), "a b")
        XCTAssertEqual(DictationText.join("a", ""), "a")
    }
    func testReadAloudCleaned() {
        let md = """
        Fertig. Die Datei liegt unter `/home/martin/relay-ios/docs/nachtlog.md`:

        ```swift
        let x = 1
        ```

        | Schritt | Ergebnis |
        |---|---|
        | Bauen | grün |

        - **Erstens** siehe [Doku](https://example.com/a) und https://example.com/b
        - Zweitens scripts/make_source.py und ChatView.swift:120

        > Zitat

        ---

        ## Ende
        """
        let t = ReadAloud.cleaned(md)
        XCTAssertFalse(t.contains("let x"), t)
        XCTAssertTrue(t.contains("Codeblock ausgelassen."), t)
        XCTAssertTrue(t.contains("liegt unter nachtlog.md:"), t)
        XCTAssertFalse(t.contains("/home/"), t)
        XCTAssertFalse(t.contains("|"), t)
        XCTAssertTrue(t.contains("Schritt, Ergebnis."), t)
        XCTAssertTrue(t.contains("Bauen, grün."), t)
        XCTAssertFalse(t.contains("---"), t)
        XCTAssertFalse(t.contains("**"), t)
        XCTAssertTrue(t.contains("Erstens siehe Doku und Link"), t)
        XCTAssertFalse(t.contains("https://"), t)
        XCTAssertTrue(t.contains("Zweitens make_source.py und ChatView.swift:120"), t)
        XCTAssertFalse(t.contains("scripts/"), t)
        XCTAssertTrue(t.contains("\nZitat"), t)
        XCTAssertTrue(t.hasSuffix("Ende"), t)
        XCTAssertFalse(t.contains("#"), t)
        XCTAssertEqual(ReadAloud.cleaned("km/h und/oder 07/11 und a/b"), "km/h und/oder 07/11 und a/b")
        XCTAssertEqual(ReadAloud.cleaned("Siehe /tmp/x/."), "Siehe x.")
        XCTAssertEqual(ReadAloud.cleaned("Ordner ~/Dokumente/privat/ aufräumen"), "Ordner privat aufräumen")
        XCTAssertEqual(ReadAloud.cleaned("Pfad `./a/b.txt:12:3` fehlt"), "Pfad b.txt fehlt")
        XCTAssertEqual(ReadAloud.cleaned("```\nnie zu"), "Codeblock ausgelassen.")
        XCTAssertEqual(ReadAloud.pathName("/"), "Pfad")
    }

    func testReadAloudQuestion() {
        let md = """
        Ich habe die CI repariert und die Tests laufen.

        Offen ist der Neustart. Optionen:
        1. Jetzt neu starten
        2. Bis morgen warten

        Soll ich `notifyd` jetzt neu starten?

        Empfehlung: ja, die Sitzungen sind beendet.
        """
        let q = try! XCTUnwrap(ReadAloud.question(in: md))
        XCTAssertTrue(q.hasPrefix("Offen ist der Neustart. Optionen:"), q)
        XCTAssertTrue(q.contains("1. Jetzt neu starten"), q)
        XCTAssertTrue(q.contains("Soll ich notifyd jetzt neu starten?"), q)
        XCTAssertTrue(q.contains("Empfehlung: ja"), q)
        XCTAssertFalse(q.contains("CI repariert"), q)

        // options after the question, the recommendation further down
        let after = "Zwei Wege.\n\nWelche Variante?\n- A: schnell\n- B: gründlich\n\nBeides geht heute.\n\nIch empfehle B."
        let a = try! XCTUnwrap(ReadAloud.question(in: after))
        XCTAssertTrue(a.hasPrefix("Welche Variante?"), a)
        XCTAssertTrue(a.contains("A: schnell"), a)
        XCTAssertTrue(a.contains("Ich empfehle B."), a)
        XCTAssertFalse(a.contains("Beides geht heute"), a)
        XCTAssertFalse(a.contains("Zwei Wege"), a)

        // a decision without a question mark
        let d = try! XCTUnwrap(ReadAloud.question(in: "Alles gebaut.\n\nEntscheidung nötig: Variante A oder B.\n\nEmpfehlung: A."))
        XCTAssertTrue(d.hasPrefix("Entscheidung nötig"), d)
        XCTAssertTrue(d.contains("Empfehlung: A."), d)

        // nothing asked, a question inside code does not count
        XCTAssertNil(ReadAloud.question(in: "Alles erledigt. Die Tests sind grün."))
        XCTAssertNil(ReadAloud.question(in: "```\nwarum?\n```\nFertig."))
        XCTAssertNil(ReadAloud.question(in: ""))
    }

    func testReadAloudSpoken() {
        let rq = AgentQuestion(agent: "relay-ios", id: "R1", question: "Soll ich weitermachen?", context: "Lange Begründung", recommendation: "ja")
        XCTAssertEqual(ReadAloud.spoken(rq), "Soll ich weitermachen?\nEmpfehlung: ja")
        XCTAssertEqual(ReadAloud.spoken(AgentQuestion(agent: "a", id: "M2", question: "Fertig.")), "Fertig.")
        let q = Question.from(["question": "Welches Modell?", "header": "Modell",
                               "options": [["label": "Opus", "description": "stark"], ["label": "Haiku"]]])!
        XCTAssertEqual(ReadAloud.spoken(question: q), "Welches Modell?\n1. Opus: stark\n2. Haiku")
        let msgs = [TMessage.from(["id": "1", "role": "user", "text": "Hallo"]),
                    TMessage.from(["id": "2", "role": "assistant", "text": "Antwort eins"]),
                    TMessage.from(["id": "3", "role": "tool", "text": "x"]),
                    TMessage.from(["id": "4", "role": "assistant", "text": "  "])]
        XCTAssertEqual(ReadAloud.lastAnswer(msgs)?.id, "2")
        XCTAssertNil(ReadAloud.lastAnswer([msgs[0]]))
    }
}
