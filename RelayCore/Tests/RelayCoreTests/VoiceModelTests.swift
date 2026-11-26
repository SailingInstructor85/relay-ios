import XCTest
@testable import RelayCore

final class VoiceModelTests: XCTestCase {
    private func listing(_ rows: [[String: Any]]) -> Data { try! JSONSerialization.data(withJSONObject: rows) }

    func testListingKeepsOnlyNeededFiles() {
        let data = listing([
            ["type": "directory", "path": "Vocoder.mlpackage", "size": 0],
            ["type": "file", "path": "Vocoder.mlpackage/Manifest.json", "size": 600],
            ["type": "file", "path": "Vocoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin", "size": 100_000_000],
            ["type": "file", "path": "TextEncoder.mlpackage/Manifest.json", "size": 600],
            ["type": "file", "path": "DurationPredictor.mlpackage/Manifest.json", "size": 600],
            ["type": "file", "path": "VectorEstimator.mlpackage/Manifest.json", "size": 600],
            ["type": "file", "path": "voice_styles/M2.json", "size": 300_000],
            ["type": "file", "path": "voice_styles/F1.json", "size": 300_000],
            ["type": "file", "path": "tts.json", "size": 2000],
            ["type": "file", "path": "unicode_indexer.json", "size": 400_000],
            ["type": "file", "path": "README.md", "size": 5000],
            ["type": "file", "path": "../../Library/Preferences/x.plist", "size": 10],
        ])
        let files = VoiceModel.files(listing: data)!
        XCTAssertEqual(files.count, 8)
        XCTAssertFalse(files.contains { $0.path.contains("F1") || $0.path == "README.md" || $0.path.contains("..") })
        XCTAssertEqual(VoiceModel.totalBytes(files), 100_000_000 + 4 * 600 + 300_000 + 2000 + 400_000)
        XCTAssertEqual(VoiceModel.missing(in: files), [])
    }

    func testListingRejectsGarbage() {
        XCTAssertNil(VoiceModel.files(listing: Data("<html>".utf8)))
        XCTAssertNil(VoiceModel.files(listing: Data("{\"error\":\"x\"}".utf8)))
        XCTAssertEqual(VoiceModel.files(listing: Data("[]".utf8)), [])
    }

    func testMissingNamesWhatIsNotThere() {
        let files = [VoiceModel.File(path: "tts.json", size: 1), VoiceModel.File(path: "Vocoder.mlpackage/Manifest.json", size: 1)]
        let missing = VoiceModel.missing(in: files)
        XCTAssertTrue(missing.contains("voice_styles/M2.json"))
        XCTAssertTrue(missing.contains("unicode_indexer.json"))
        XCTAssertTrue(missing.contains("TextEncoder.mlpackage"))
        XCTAssertFalse(missing.contains("Vocoder.mlpackage"))
        XCTAssertFalse(missing.contains("tts.json"))
    }

    func testPathsStayInsideTheFolder() {
        XCTAssertTrue(VoiceModel.safe("Vocoder.mlpackage/Data/weights/weight.bin"))
        XCTAssertFalse(VoiceModel.safe("/etc/passwd"))
        XCTAssertFalse(VoiceModel.safe("Vocoder.mlpackage/../../x"))
        XCTAssertFalse(VoiceModel.safe("Vocoder.mlpackage//x"))
        XCTAssertFalse(VoiceModel.safe("./tts.json"))
        XCTAssertFalse(VoiceModel.safe(""))
        XCTAssertFalse(VoiceModel.wanted("Vocoder.mlpackage/../tts.json"))
        XCTAssertFalse(VoiceModel.wanted("Vocoder.mlpackagex/a"))
        XCTAssertNil(VoiceModel.fileURL("../x"))
        XCTAssertEqual(VoiceModel.fileURL("voice_styles/M2.json")?.absoluteString,
                       "https://huggingface.co/aufklarer/Supertonic-3-CoreML/resolve/main/voice_styles/M2.json")
    }

    func testNextPageOnlyOnTheSameServer() {
        let ok = "<https://huggingface.co/api/models/a/b/tree/main?recursive=true&cursor=abc>; rel=\"next\""
        XCTAssertEqual(VoiceModel.nextPage(link: ok)?.host, "huggingface.co")
        XCTAssertNil(VoiceModel.nextPage(link: "<https://example.org/x>; rel=\"next\""))
        XCTAssertNil(VoiceModel.nextPage(link: "<https://huggingface.co/x>; rel=\"prev\""))
        XCTAssertNil(VoiceModel.nextPage(link: nil))
    }

    func testSizeAndSpeed() {
        XCTAssertEqual(VoiceModel.sizeText(412_300_000), "412 MB")
        XCTAssertEqual(VoiceModel.sizeText(1_200_000_000), "1,2 GB")
        XCTAssertEqual(VoiceModel.speed(tempo: 1.0), 1.05, accuracy: 0.001)
        XCTAssertEqual(VoiceModel.speed(tempo: 9), 1.575, accuracy: 0.001)
    }

    func testSpokenTurnsNumbersIntoWords() {
        XCTAssertEqual(VoiceModel.spoken("Es sind 1081 Dateien."), "Es sind eintausendeinundachtzig Dateien.")
    }

    // MARK: Rechenweg (Messung vom 25.11.2026: im Hintergrund verweigert iOS den Grafikchip)

    private let denied = "Error Domain=com.apple.CoreML Code=0 \"Unable to compute the prediction using ML Program. It can be an invalid input data or broken/unsupported model.\" UserInfo={NSUnderlyingError=0x11c227000 {Error Domain=com.apple.CoreML Code=0 \"E5RT: GPU sync execute failed: Insufficient Permission (to submit GPU work from background) (00000006:kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted) (11)\"}}"

    func testComputeUnitsFollowForeground() {
        let c = VoiceCompute()
        XCTAssertEqual(c.units(foreground: true), .all)
        XCTAssertEqual(c.units(foreground: false), .cpu)
    }

    func testBackgroundDeniedIsRecognised() {
        XCTAssertTrue(VoiceCompute.backgroundDenied(denied))
        XCTAssertFalse(VoiceCompute.backgroundDenied("Supertonic: inference failed — missing output 'wav'"))
        XCTAssertFalse(VoiceCompute.backgroundDenied(""))
    }

    func testRetryAfterBackgroundDenialKeepsGraphicsChipForLater() {
        // der Bildschirm ging während der Berechnung aus: zweiter Versuch auf dem Prozessor, vorn wieder alles
        var c = VoiceCompute()
        c.succeeded(with: .all, firstError: denied)
        XCTAssertFalse(c.cpuOnly)
        XCTAssertEqual(c.units(foreground: true), .all)
        XCTAssertEqual(c.failures, 0)
    }

    func testOtherFailureInForegroundStaysOnProcessor() {
        var c = VoiceCompute()
        c.succeeded(with: .all, firstError: "Unable to compute the prediction using ML Program.")
        XCTAssertTrue(c.cpuOnly)
        XCTAssertEqual(c.units(foreground: true), .cpu)
        c.reset()
        XCTAssertEqual(c.units(foreground: true), .all)
    }

    func testSuccessWithoutRetryChangesNothing() {
        var c = VoiceCompute()
        c.succeeded(with: .all, firstError: nil)
        c.succeeded(with: .cpu, firstError: nil)
        // ein zweiter Versuch auf dem Prozessor nach einem Fehler auf dem Prozessor sagt nichts über den Grafikchip
        c.succeeded(with: .cpu, firstError: "kaputt")
        XCTAssertFalse(c.cpuOnly)
    }

    func testTwoFailedSentencesInARowRest() {
        var c = VoiceCompute()
        XCTAssertFalse(c.failed())
        c.succeeded(with: .cpu, firstError: nil)
        XCTAssertFalse(c.failed())
        XCTAssertTrue(c.failed())
        c.reset()
        XCTAssertEqual(c.failures, 0)
    }

    func testRestingEndsWithTheNextReply() {
        // zwei Sätze scheitern ganz: Supertonic ruht für den Rest der Antwort
        var c = VoiceCompute()
        XCTAssertFalse(c.resting)
        XCTAssertFalse(c.failed())
        XCTAssertFalse(c.resting)
        XCTAssertTrue(c.failed())
        XCTAssertTrue(c.resting)
        // weitere Fehler ändern daran nichts
        XCTAssertTrue(c.failed())
        // die nächste Antwort beginnt: wieder Supertonic, wie nach einem frischen Start
        XCTAssertTrue(c.revive())
        XCTAssertFalse(c.resting)
        XCTAssertEqual(c.failures, 0)
        XCTAssertEqual(c.units(foreground: true), .all)
        XCTAssertEqual(c, VoiceCompute())
        // danach zählt es wieder von vorn: ein einzelner Fehler lässt Supertonic nicht ruhen
        XCTAssertFalse(c.failed())
        XCTAssertFalse(c.resting)
    }

    func testReviveWithoutRestKeepsWhatWasLearned() {
        var c = VoiceCompute()
        XCTAssertFalse(c.revive())
        c.succeeded(with: .all, firstError: "Unable to compute the prediction using ML Program.")
        XCTAssertFalse(c.failed())
        XCTAssertFalse(c.revive())
        // ohne Ruhe bleibt der Prozessor gemerkt und der eine Fehler gezählt
        XCTAssertTrue(c.cpuOnly)
        XCTAssertEqual(c.failures, 1)
    }

    func testRevivedAfterProcessorOnlyStartsWithEverything() {
        var c = VoiceCompute()
        c.succeeded(with: .all, firstError: "kaputt")
        XCTAssertTrue(c.cpuOnly)
        _ = c.failed()
        _ = c.failed()
        XCTAssertTrue(c.revive())
        XCTAssertFalse(c.cpuOnly)
    }

    func testFallbackLineNamesSentenceStartPlaceAndReason() {
        let s = "Beides kommt ins Relay-Backlog, der Nachtbau setzt es dann um."
        let line = VoiceCompute.fallbackLine(sentence: s, reason: denied, foreground: false)
        XCTAssertTrue(line.hasPrefix("Apple-Stimme statt Supertonic (App im Hintergrund): „Beides kommt ins Relay-Backlog, der Nach…“. Grund: "), line)
        XCTAssertFalse(line.contains("setzt es dann um"))
        let front = VoiceCompute.fallbackLine(sentence: "Kurz.\nZweite Zeile", reason: "Modell lädt", foreground: true)
        XCTAssertEqual(front, "Apple-Stimme statt Supertonic (App vorn): „Kurz. Zweite Zeile“. Grund: Modell lädt")
        // lange Fehlermeldungen von iOS werden gekürzt
        let long = VoiceCompute.fallbackLine(sentence: "Hallo", reason: String(repeating: "x", count: 900), foreground: true)
        XCTAssertTrue(long.hasSuffix("…"))
        XCTAssertLessThan(long.count, 300)
    }

    func testTimingNote() {
        XCTAssertEqual(VoiceCompute.timingNote(processor: false, foreground: true), "")
        XCTAssertEqual(VoiceCompute.timingNote(processor: true, foreground: true), ", Prozessor")
        XCTAssertEqual(VoiceCompute.timingNote(processor: true, foreground: false), ", Prozessor, App im Hintergrund")
    }

    func testKeptLogDropsTheOldest() {
        XCTAssertEqual(KeptLog.appended([1, 2], 3), [1, 2, 3])
        XCTAssertEqual(KeptLog.appended([1, 2, 3], 4, limit: 3), [2, 3, 4])
        XCTAssertEqual(KeptLog.appended([Int](), 1, limit: 0), [1])
        XCTAssertEqual(KeptLog.appended(Array(1...100), 101).count, KeptLog.limit)
    }

    func testBriefShortensLongErrors() {
        XCTAssertEqual(VoiceCompute.brief("kurz"), "kurz")
        XCTAssertEqual(VoiceCompute.brief("a\nb"), "a b")
        let long = VoiceCompute.brief(String(repeating: "x", count: 900))
        XCTAssertEqual(long.count, 301)
        XCTAssertTrue(long.hasSuffix("…"))
    }
}
