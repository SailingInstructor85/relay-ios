import SwiftUI
import AVFoundation
import RelayCore

/// Reads finished sessions aloud (own speech engine, separate from Jarvis and the chat).
@MainActor
final class Announcer {
    static let shared = Announcer()
    let voice = VoiceIO()
    var busy = false
}

extension AppModel {
    /// Headphones, a Bluetooth headset or CarPlay on the current audio route.
    static var headphonesConnected: Bool {
        let types: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .carAudio]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { types.contains($0.portType) }
    }

    /// A session just finished: with the setting on, in the foreground, and headphones or conversation mode, read a short
    /// summary aloud (rpc `speak_summary`; the first sentences of the last message when that fails).
    func announceFinished(_ s: Session) {
        guard SpeechPrefs.readFinished, foreground, state == .connected, !Announcer.shared.busy, !driveActive,
              s.key != visibleChat, conversationActive || Self.headphonesConnected else { return }
        let a = Announcer.shared
        a.busy = true
        Task { @MainActor in
            defer { a.busy = false }
            var text = ""
            if let t = try? await summarize(s) { text = t }
            if text.isEmpty { text = SpeechText.brief(s.lastMessage) }
            guard !text.isEmpty, foreground else { return }
            a.voice.speak("\(s.name). \(text)")
            await a.voice.waitUntilSpoken()
            a.voice.releaseAudio()  // vorgelesen: Musik anderer Apps läuft weiter
        }
    }

    /// `jarvis_warm` at most every 30 s while connected; not retried once the Desktop said "unknown rpc".
    func warmJarvis() {
        guard state == .connected, !jarvisWarmUnsupported, Date().timeIntervalSince(lastJarvisWarm) > 30 else { return }
        lastJarvisWarm = Date()
        Task {
            do { _ = try await rpc("jarvis_warm", [:], timeout: 10) }
            catch { if error.localizedDescription.lowercased().contains("unknown rpc") { jarvisWarmUnsupported = true } }
        }
    }

    /// "Erkennung korrigieren": adds a term, or the correction "heard => meant", then reloads the vocabulary.
    func teachVocab(heard: String, meant: String, into voice: VoiceIO) async throws {
        var p: [String: JSON] = ["meant": .string(meant.trimmingCharacters(in: .whitespacesAndNewlines))]
        let h = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        if !h.isEmpty { p["heard"] = .string(h) }
        _ = try await rpc("voice_vocab_add", .object(p), timeout: 15)
        await loadVocab(into: voice)
    }

    /// Latency of a voice turn to the Desktop (rpc `voice_timing`); failures and old gateways are ignored.
    func sendVoiceTiming(trigger: String, stages: [String: Int]) {
        guard state == .connected else { return }
        let st = JSON.object(stages.mapValues { JSON.number(Double($0)) })
        Task { _ = try? await rpc("voice_timing", ["trigger": .string(trigger), "stt": "device", "stages": st], timeout: 10) }
    }
}
