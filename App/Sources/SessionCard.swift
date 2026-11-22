import SwiftUI
import RelayCore

/// Avatar einer Sitzung im neuen Design: Zeichen oder Kürzel des Projekts im Farbkreis (40 pt, außen 48 pt Platz
/// für den Ring). Ring in Akzentfarbe, wenn gearbeitet wird; roter Punkt mit „!“, wenn die Sitzung wartet;
/// Akzentpunkt oben rechts bei Ungelesenem. Der Ring steht still (keine Daueranimation).
struct SessionCardAvatar: View {
    let cwd: String
    let title: String
    let status: Today.Status
    var unread = false
    var stale = false
    var look = Avatars.Look()
    var size: CGFloat = RelaySpace.avatar

    var body: some View {
        let glyph = Avatars.glyph(cwd: cwd, title: title, look: look)
        let emoji = glyph?.unicodeScalars.contains { $0.value > 0x2000 } ?? false
        let fill: Color = stale ? RelayColor.outline : Color(hex: Avatars.color(cwd: cwd, look: look))
        let outer = size + 8
        ZStack {
            if status == .working && !stale {
                Circle().stroke(RelayColor.primary.opacity(0.15), lineWidth: 2.5)
                Circle().trim(from: 0, to: 0.7).stroke(RelayColor.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Circle().fill(fill).frame(width: size, height: size)
            if emoji {
                Text(glyph ?? "").font(.system(size: size * 0.5))
            } else {
                Text(glyph ?? Avatars.initials(cwd)).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: outer, height: outer)
        .overlay(alignment: .bottomTrailing) {
            if status == .waits && !stale {
                Text("!").font(.system(size: 11, weight: .bold)).foregroundStyle(RelayColor.onError)
                    .frame(width: 16, height: 16)
                    .background(RelayColor.error, in: Circle())
                    .overlay { Circle().stroke(RelayColor.background, lineWidth: 2) }
            }
        }
        .overlay(alignment: .topTrailing) {
            if unread && status != .waits {
                Circle().fill(RelayColor.primary).frame(width: 11, height: 11)
                    .overlay { Circle().stroke(RelayColor.background, lineWidth: 2) }
                    .offset(x: -2, y: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Eine Sitzung als Karte auf „Heute“: Avatar im Farbkreis, Name in Serif, daneben „modell · ctx“, rechts das Alter,
/// darunter Status in Farbe und der zweizeilige Kurztext. Die Daten kommen aus `Today.Row` (RelayCore).
struct SessionCard: View {
    let row: Today.Row
    var look = Avatars.Look()
    /// Liste ohne Verbindung: alles grau, der Stand ist der zuletzt bekannte.
    var stale = false
    var now = Date()

    private var statusColor: Color {
        if stale { return RelayColor.outline }
        switch row.status {
        case .waits: return RelayColor.error
        case .working: return RelayColor.primary
        case .idle: return RelayColor.outline
        }
    }

    private var metaColor: Color {
        row.contextLevel >= 2 ? RelayColor.error : (row.contextLevel == 1 ? RelayColor.levelHigh : RelayColor.onSurfaceVariant)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SessionCardAvatar(cwd: row.cwd, title: row.title, status: row.status, unread: row.unread, stale: stale, look: look)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if row.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(RelayColor.levelHigh).accessibilityLabel("angeheftet")
                    }
                    Text(row.title).font(RelayFont.titleMedium).fontWeight(row.unread ? .semibold : .medium)
                        .foregroundStyle(RelayColor.onSurface).lineLimit(1).layoutPriority(1)
                    if !row.meta.isEmpty {
                        Text(row.meta).font(RelayFont.labelSmall).fontWeight(row.contextLevel > 0 ? .bold : .medium)
                            .foregroundStyle(metaColor).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(TermText.ago(row.lastActivity, now: now)).font(RelayFont.labelMedium)
                        .foregroundStyle(row.unread ? RelayColor.primary : RelayColor.onSurfaceVariant).lineLimit(1).layoutPriority(1)
                }
                (Text(row.statusText).foregroundColor(statusColor)
                 + Text(row.preview.isEmpty ? "" : "  ·  " + row.preview).foregroundColor(RelayColor.onSurfaceVariant))
                    .font(RelayFont.bodyMedium).lineLimit(2).multilineTextAlignment(.leading)
            }
            .padding(.top, 5)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .relayCard(row.status == .waits && !stale ? RelayColor.waitingTint : RelayColor.background)
        .padding(.horizontal, RelaySpace.rowOuter)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
