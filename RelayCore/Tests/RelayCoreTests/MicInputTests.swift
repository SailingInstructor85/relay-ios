import XCTest
@testable import RelayCore

final class MicInputTests: XCTestCase {
    private let builtIn = MicInput.Format(sampleRate: 48000, channels: 1)
    private let car = MicInput.Format(sampleRate: 16000, channels: 1)

    func testUsable() {
        XCTAssertTrue(MicInput.usable(builtIn))
        XCTAssertTrue(MicInput.usable(car))
        XCTAssertTrue(MicInput.usable(.init(sampleRate: 8000, channels: 2)))
        // während die Verbindung wechselt, meldet iOS kurz nichts Brauchbares
        XCTAssertFalse(MicInput.usable(.init(sampleRate: 0, channels: 1)))
        XCTAssertFalse(MicInput.usable(.init(sampleRate: 48000, channels: 0)))
        XCTAssertFalse(MicInput.usable(.init(sampleRate: -1, channels: 1)))
        XCTAssertFalse(MicInput.usable(.init(sampleRate: .nan, channels: 1)))
        XCTAssertFalse(MicInput.usable(.init(sampleRate: .infinity, channels: 1)))
    }

    func testLabel() {
        XCTAssertEqual(car.label, "16000 Hz, 1 Kanal")
        XCTAssertEqual(MicInput.Format(sampleRate: 44100, channels: 2).label, "44100 Hz, 2 Kanäle")
        XCTAssertEqual(MicInput.Format(sampleRate: .nan, channels: 0).label, "0 Hz, 0 Kanäle")
    }

    func testMessages() {
        XCTAssertEqual(MicInput.message(.format(.init(sampleRate: 0, channels: 0))), MicInput.changing)
        XCTAssertEqual(MicInput.message(.exception("Failed to create tap due to format mismatch")), MicInput.changing)
        XCTAssertEqual(MicInput.message(.start("error 561015905")), MicInput.notReady)
        XCTAssertTrue(MicInput.changing.contains("noch einmal tippen"))
    }

    func testLogLine() {
        XCTAssertEqual(MicInput.logLine(.format(.init(sampleRate: 0, channels: 1))), "format unbrauchbar: 0 Hz, 1 Kanal")
        XCTAssertEqual(MicInput.logLine(.exception("format mismatch")), "ausnahme: format mismatch")
        XCTAssertEqual(MicInput.logLine(.start("nicht aktiv")), "start: nicht aktiv")
    }

    /// Eine Meldung, aber nichts hat sich für die Aufnahme geändert (etwa der Lautsprecher wechselt): weiterlaufen.
    func testNoRestartWhenNothingChanged() {
        XCTAssertFalse(MicInput.needsRestart(running: true, tap: builtIn, hardware: builtIn))
        XCTAssertFalse(MicInput.needsRestart(running: true, tap: car, hardware: car))
    }

    /// Das Auto verbindet sich mitten in der Aufnahme: anderes Format, neu einrichten.
    func testRestartWhenFormatChanged() {
        XCTAssertTrue(MicInput.needsRestart(running: true, tap: builtIn, hardware: car))
        XCTAssertTrue(MicInput.needsRestart(running: true, tap: car, hardware: builtIn))
        XCTAssertTrue(MicInput.needsRestart(running: true, tap: builtIn, hardware: .init(sampleRate: 48000, channels: 2)))
    }

    /// iOS hat die Aufnahme angehalten, oder das Format ist nicht lesbar: neu einrichten.
    func testRestartWhenStoppedOrUnknown() {
        XCTAssertTrue(MicInput.needsRestart(running: false, tap: builtIn, hardware: builtIn))
        XCTAssertTrue(MicInput.needsRestart(running: true, tap: nil, hardware: builtIn))
        XCTAssertTrue(MicInput.needsRestart(running: true, tap: builtIn, hardware: nil))
        XCTAssertTrue(MicInput.needsRestart(running: true, tap: builtIn, hardware: .init(sampleRate: 0, channels: 0)))
    }

    func testRetryDelays() {
        XCTAssertEqual(MicInput.retryDelay(afterFailed: 0), 0.3)
        XCTAssertEqual(MicInput.retryDelay(afterFailed: MicInput.retryDelays.count - 1), MicInput.retryDelays.last)
        XCTAssertNil(MicInput.retryDelay(afterFailed: MicInput.retryDelays.count))
        XCTAssertNil(MicInput.retryDelay(afterFailed: -1))
        // insgesamt nur kurz: Wer aufs Mikrofon tippt, wartet nicht lange auf eine Fehlermeldung
        XCTAssertLessThanOrEqual(MicInput.retryDelays.reduce(0, +), 2.5)
    }
}
