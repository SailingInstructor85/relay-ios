import XCTest
@testable import RelayCore

final class SpokenNumbersTests: XCTestCase {
    func testCardinal() {
        XCTAssertEqual(SpokenNumbers.cardinal(0), "null")
        XCTAssertEqual(SpokenNumbers.cardinal(1), "eins")
        XCTAssertEqual(SpokenNumbers.cardinal(16), "sechzehn")
        XCTAssertEqual(SpokenNumbers.cardinal(21), "einundzwanzig")
        XCTAssertEqual(SpokenNumbers.cardinal(30), "dreißig")
        XCTAssertEqual(SpokenNumbers.cardinal(101), "einhunderteins")
        XCTAssertEqual(SpokenNumbers.cardinal(1001), "eintausendeins")
        XCTAssertEqual(SpokenNumbers.cardinal(1081), "eintausendeinundachtzig")
        XCTAssertEqual(SpokenNumbers.cardinal(100_000), "einhunderttausend")
        XCTAssertEqual(SpokenNumbers.cardinal(2_000_000), "zwei Millionen")
        XCTAssertEqual(SpokenNumbers.cardinal(1_100_000_000), "eine Milliarde einhundert Millionen")
    }

    func testPlainNumbers() {
        XCTAssertEqual(SpokenNumbers.german("Es sind 1081 Zeilen."), "Es sind eintausendeinundachtzig Zeilen.")
        XCTAssertEqual(SpokenNumbers.german("1.081 Zeilen und 1.000.000 Euro"), "eintausendeinundachtzig Zeilen und eine Million Euro")
        XCTAssertEqual(SpokenNumbers.german("600 KB, 100.000 Zeichen"), "sechshundert KB, einhunderttausend Zeichen")
        XCTAssertEqual(SpokenNumbers.german("Es sind 3. Danach 7."), "Es sind drei. Danach sieben.")
        XCTAssertEqual(SpokenNumbers.german("geboren 1985"), "geboren neunzehnhundertfünfundachtzig")
        XCTAssertEqual(SpokenNumbers.german("-5 Grad, 3-5 Tage"), "minus fünf Grad, drei-fünf Tage")
    }

    func testIdsAndLetters() {
        // an Buchstaben hängende Ziffern bleiben, lange Nummern und führende Nullen Ziffer für Ziffer
        XCTAssertEqual(SpokenNumbers.german("R1 und M2 bleiben, 2da5687 auch"), "R1 und M2 bleiben, 2da5687 auch")
        XCTAssertEqual(SpokenNumbers.german("iOS 18"), "iOS achtzehn")
        XCTAssertEqual(SpokenNumbers.german("Lauf 0830"), "Lauf null acht drei null")
        XCTAssertEqual(SpokenNumbers.german("Lauf 45349872405"), "Lauf vier fünf drei vier neun acht sieben zwei vier null fünf")
    }

    func testDatesAndTimes() {
        XCTAssertEqual(SpokenNumbers.german("Termin am 24.11.2026 um 14:30 Uhr"),
                       "Termin am vierundzwanzigsten November zweitausendsechsundzwanzig um vierzehn Uhr dreißig")
        XCTAssertEqual(SpokenNumbers.german("Der 24.11. ist ein Dienstag, 09:00 passt"),
                       "Der vierundzwanzigste November ist ein Dienstag, neun Uhr passt")
        XCTAssertEqual(SpokenNumbers.german("am 01.02.1985"), "am ersten Februar neunzehnhundertfünfundachtzig")
        XCTAssertEqual(SpokenNumbers.german("Um 1:05 und 0:30"), "Um ein Uhr fünf und null Uhr dreißig")
        XCTAssertEqual(SpokenNumbers.german("24.11."), "vierundzwanzigster November")
    }

    func testOrdinals() {
        XCTAssertEqual(SpokenNumbers.german("am 3. Dezember, der 1. Platz, den 2. Versuch"),
                       "am dritten Dezember, der erste Platz, den zweiten Versuch")
    }

    func testVersionsAndDots() {
        XCTAssertEqual(SpokenNumbers.german("Version 0.4.4 ist da, v0.4.5 folgt"),
                       "Version null Punkt vier Punkt vier ist da, null Punkt vier Punkt fünf folgt")
        XCTAssertEqual(SpokenNumbers.german("Das dauert 0.15 Sekunden."), "Das dauert null Punkt fünfzehn Sekunden.")
        XCTAssertEqual(SpokenNumbers.german("1.2.3"), "eins Punkt zwei Punkt drei")
    }

    func testMoneyAndPercent() {
        XCTAssertEqual(SpokenNumbers.german("Es kostet 12,50 € oder 1 € oder 300 EUR"),
                       "Es kostet zwölf Euro fünfzig oder ein Euro oder dreihundert Euro")
        XCTAssertEqual(SpokenNumbers.german("Zu 50 % voll, 3,14 genau"), "Zu fünfzig Prozent voll, drei Komma eins vier genau")
    }

    func testTextWithoutNumbersStays() {
        let s = "Guten Morgen, Martin. Das Gateway läuft."
        XCTAssertEqual(SpokenNumbers.german(s), s)
    }
}
