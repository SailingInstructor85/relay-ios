import SwiftUI

/// The 1 to 3 sentence summary of a session (rpc `speak_summary`) as a card at the bottom of its chat.
struct SummaryState: Equatable {
    var loading = false
    var text = ""
    var error: String?
}

struct SummaryCard: View {
    let state: SummaryState
    let speaking: Bool
    let onSpeak: (String) -> Void
    let onStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Zusammenfassung", systemImage: "text.alignleft").font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                Spacer()
                if !state.text.isEmpty {
                    Button { speaking ? onStop() : onSpeak(state.text) } label: { Image(systemName: speaking ? "stop.circle" : "speaker.wave.2") }
                        .accessibilityLabel(speaking ? "Vorlesen beenden" : "Vorlesen")
                }
                Button(action: onClose) { Image(systemName: "xmark") }.accessibilityLabel("Schließen")
            }
            if state.loading {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Fasse zusammen…").font(.callout).foregroundStyle(.secondary) }
            } else if let e = state.error {
                Text(e).font(.callout).foregroundStyle(.red)
            } else {
                Text(state.text).font(.callout).textSelection(.enabled)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor.opacity(0.3)))
        .padding(.horizontal).padding(.vertical, 4)
    }
}
