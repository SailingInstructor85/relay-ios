// Übernommen aus speech-swift (soniqo), Modul SupertonicTTS, Stand v0.0.29, Apache-Lizenz 2.0 (siehe NOTICE).
// Geändert für Relay: ohne das Modul AudioCommon (kein Download über das Paket, keine Umgebungsvariable für die
// Recheneinheiten), sonst unverändert.
import Foundation

public enum SupertonicError: Error, CustomStringConvertible {
    case badAsset(String)
    case unsupportedLanguage(String)
    case missingFile(String)
    case inference(String)
    case voiceNotFound(String)

    public var description: String {
        switch self {
        case .badAsset(let s): return "Supertonic: bad asset — \(s)"
        case .unsupportedLanguage(let l): return "Supertonic: unsupported language '\(l)'"
        case .missingFile(let f): return "Supertonic: missing file \(f)"
        case .inference(let s): return "Supertonic: inference failed — \(s)"
        case .voiceNotFound(let v): return "Supertonic: unknown voice '\(v)'"
        }
    }
}
