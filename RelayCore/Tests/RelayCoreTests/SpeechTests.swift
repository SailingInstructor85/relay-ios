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
}
