import XCTest
@testable import RelayCore

final class SpokenWordsTests: XCTestCase {
    func testChief() {
        XCTAssertEqual(SpokenWords.respell("Der Chief ist bereit."), "Der Tschief ist bereit.")
        XCTAssertEqual(SpokenWords.respell("Chief, was steht an?"), "Tschief, was steht an?")
        XCTAssertEqual(SpokenWords.respell("Frag den chief."), "Frag den Tschief.")
        XCTAssertEqual(SpokenWords.respell("die Notizen des Chiefs"), "die Notizen des Tschiefs")
        XCTAssertEqual(SpokenWords.respell("die Chief-Sitzung"), "die Tschief-Sitzung")
        XCTAssertEqual(SpokenWords.respell("„Chief“ und (Chief)"), "„Tschief“ und (Tschief)")
    }

    func testOnlyWholeWords() {
        for s in ["Chiefsache", "Mischief", "Chief2", "3Chief", "Der Chef ist da.", ""] {
            XCTAssertEqual(SpokenWords.respell(s), s)
        }
    }

    func testOwnList() {
        let list = ["KI": "Ka-I", "KI-Firma": "Ka-I Firma", "a.b": "a Punkt b", "Wert": "$0 \\ Wert"]
        // längster Eintrag zuerst
        XCTAssertEqual(SpokenWords.respell("Die KI-Firma und die KI.", list: list), "Die Ka-I Firma und die Ka-I.")
        // Sonderzeichen im Wort und in der Schreibweise gelten wörtlich
        XCTAssertEqual(SpokenWords.respell("a.b und axb", list: list), "a Punkt b und axb")
        XCTAssertEqual(SpokenWords.respell("Wert", list: list), "$0 \\ Wert")
        XCTAssertEqual(SpokenWords.respell("Text bleibt.", list: [:]), "Text bleibt.")
    }

    func testVoiceModelUsesList() {
        XCTAssertEqual(VoiceModel.spoken("Der Chief meldet 3 Punkte."), "Der Tschief meldet drei Punkte.")
    }
}
