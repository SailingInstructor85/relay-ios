import Foundation

/// Regeln für das Mikrofon einer Aufnahme (Diktat, Jarvis, Sprachmodus). Der Ton kommt je nach Verbindung in einem
/// anderen Format: eingebautes Mikrofon 48 kHz, Freisprechen im Auto über Bluetooth 16 kHz oder 8 kHz. Passt das
/// Format, mit dem die Aufnahme eingerichtet wird, nicht zum Gerät, wirft iOS eine Ausnahme („Failed to create tap
/// due to format mismatch“), die die App beendet hat (10.11., 16.11. und 27.11.2026). Deshalb: für jede Aufnahme
/// frisch einrichten, das Format vorher prüfen, und bei einem Wechsel mitten in der Aufnahme neu einrichten.
public enum MicInput {
    /// Abtastrate und Kanäle eines Tonformats.
    public struct Format: Equatable, Sendable {
        public let sampleRate: Double
        public let channels: Int
        public init(sampleRate: Double, channels: Int) {
            self.sampleRate = sampleRate
            self.channels = channels
        }
        /// Fürs Protokoll, z. B. „16000 Hz, 1 Kanal“.
        public var label: String { "\(Int(sampleRate.isFinite ? sampleRate : 0)) Hz, \(channels) \(channels == 1 ? "Kanal" : "Kanäle")" }
    }

    /// Mit diesem Format lässt sich aufnehmen. Während die Tonverbindung wechselt, meldet iOS kurz 0 Hz oder 0 Kanäle.
    public static func usable(_ f: Format) -> Bool {
        f.sampleRate.isFinite && f.sampleRate > 0 && f.channels > 0
    }

    /// Das Format passt gerade nicht (die Tonverbindung wechselt).
    public static let changing = "Mikrofon wechselt gerade, bitte noch einmal tippen."
    /// Die Aufnahme ließ sich aus einem anderen Grund nicht starten.
    public static let notReady = "Das Mikrofon ließ sich nicht starten, bitte noch einmal tippen."

    /// Was beim Einrichten einer Aufnahme schiefging.
    public enum Failure: Equatable, Sendable {
        /// Das Gerät meldet kein brauchbares Format.
        case format(Format)
        /// iOS hat eine Ausnahme geworfen (früher: Absturz).
        case exception(String)
        /// Die Aufnahme ließ sich nicht starten (Fehler von iOS).
        case start(String)
    }

    /// Text für den Nutzer.
    public static func message(_ f: Failure) -> String {
        switch f {
        case .format, .exception: return changing
        case .start: return notReady
        }
    }

    /// Zeile fürs Nutzungsprotokoll, damit sich ein Bericht zuordnen lässt.
    public static func logLine(_ f: Failure) -> String {
        switch f {
        case .format(let fmt): return "format unbrauchbar: " + fmt.label
        case .exception(let why): return "ausnahme: " + why
        case .start(let why): return "start: " + why
        }
    }

    /// Nach einer Meldung von iOS (Tonverbindung oder Konfiguration geändert) mitten in der Aufnahme: Muss sie neu
    /// eingerichtet werden? Ja, wenn sie steht (iOS hält sie bei einem Wechsel selbst an), wenn das Gerät kein
    /// brauchbares Format meldet oder wenn es ein anderes Format hat als das, mit dem aufgenommen wird.
    /// `tap`: Format der laufenden Aufnahme, `hardware`: was das Gerät jetzt liefert.
    public static func needsRestart(running: Bool, tap: Format?, hardware: Format?) -> Bool {
        guard running, let tap, let hardware, usable(hardware) else { return true }
        return tap != hardware
    }

    /// So lange nach einer Meldung warten, bis sich die neue Verbindung gesetzt hat. Mehrere Meldungen kurz
    /// hintereinander (iOS schickt oft zwei oder drei) führen so zu einem einzigen Neustart.
    public static let settle = 0.3

    /// Pausen vor weiteren Versuchen, wenn das Einrichten scheitert, weil das Format noch nicht steht.
    public static let retryDelays: [Double] = [0.3, 0.6, 1.0]

    /// Pause vor dem nächsten Versuch; nil = aufgeben. `attempt` zählt die gescheiterten Versuche ab 0.
    public static func retryDelay(afterFailed attempt: Int) -> Double? {
        attempt >= 0 && attempt < retryDelays.count ? retryDelays[attempt] : nil
    }
}
