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
}
