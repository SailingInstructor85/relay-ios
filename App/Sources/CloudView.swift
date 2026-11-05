import SwiftUI
import RelayCore

/// Section "Cloud-Sitzungen" in the usage page (claude.ai/code, last 30 days, rpc and event `cloud_sessions`).
struct CloudSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            if !model.cloudError.isEmpty {
                Label(model.cloudError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            if model.cloudSessions.isEmpty && model.cloudError.isEmpty {
                Text("Keine Cloud-Sitzungen in den letzten 30 Tagen").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(model.cloudSessions) { c in
                Button {
                    if let u = URL(string: c.url), !c.url.isEmpty { UIApplication.shared.open(u) }
                } label: { CloudDetailRow(c: c) }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Cloud-Sitzungen")
        } footer: {
            if model.cloudChecked > 0 { Text("Geprüft \(Date(timeIntervalSince1970: model.cloudChecked), style: .relative). Tippen öffnet die Sitzung.") }
        }
    }
}

struct CloudDetailRow: View {
    let c: CloudSession
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if c.unread { Circle().fill(Color.accentColor).frame(width: 8, height: 8) }
                Text(c.title).lineLimit(1)
                Spacer(minLength: 4)
                Text(TermText.ago(c.lastAt)).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(AccountsText.cloudState(c.state)).foregroundStyle(c.waiting ? Color.orange : Color.secondary)
                if !c.repo.isEmpty { Text("· \(c.repo)\(c.branch.isEmpty ? "" : " (\(c.branch))")").lineLimit(1) }
                if c.costUsd > 0 { Text("· \(AccountsText.money(c.costUsd, "USD"))") }
                if !c.model.isEmpty { Text("· \(c.model)").lineLimit(1) }
            }.font(.caption).foregroundStyle(.secondary)
            let q = c.question.isEmpty ? c.detail : c.question
            if !q.isEmpty { Text(q).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
        }
        .contentShape(Rectangle())
    }
}
