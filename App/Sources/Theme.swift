import SwiftUI
import UIKit

// Das Designsystem der App: festes, warmes Farbschema mit einem Akzent (Terrakotta), Serifenschrift für Titel, Namen
// und Antworten der Agenten, serifenlose Schrift für alles Bedienbare. Werte 1:1 aus der Android-App (Theme.kt),
// siehe docs/redesign/analyse-android-ui.md Abschnitt 4. Hell und Dunkel folgen dem System.

extension Color {
    /// 0xRRGGBB als sRGB-Farbe.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Eine Farbe mit eigenem Wert für Hell und Dunkel.
    static func relay(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

enum RelayColor {
    /// Akzent: Abschnittstitel, Senden-Knopf, Links, Fortschrittsring. Hell bewusst dunkler (Kontrast auf Weiß).
    static let primary                 = Color.relay(0xAE5230, 0xD97757)
    static let onPrimary               = Color.relay(0xFFFFFF, 0x2B1209)
    static let primaryContainer        = Color.relay(0xF3DDD3, 0x4A2A1D)
    static let onPrimaryContainer      = Color.relay(0x3D1E12, 0xF3DDD3)
    static let secondary               = Color.relay(0x6B6A63, 0xB8B6AC)
    static let onSecondary             = Color.relay(0xFFFFFF, 0x262624)
    static let secondaryContainer      = Color.relay(0xEDEAE0, 0x3A3935)
    static let onSecondaryContainer    = Color.relay(0x2B2A26, 0xE8E6DC)
    /// Grün mit fester Bedeutung: ruhig, bereit, erledigt.
    static let tertiary                = Color.relay(0x5B7F5E, 0x9CC29F)
    static let onTertiary              = Color.relay(0xFFFFFF, 0x12230F)
    static let tertiaryContainer       = Color.relay(0xDDE8DA, 0x2F4430)
    static let onTertiaryContainer     = Color.relay(0x1B2D1D, 0xDDE8DA)
    /// Seitenhintergrund, Titelzeile, Listenzeilen.
    static let background              = Color.relay(0xFAF9F5, 0x262624)
    static let onSurface               = Color.relay(0x1F1E1B, 0xF0EEE6)
    static let surfaceVariant          = Color.relay(0xF0EEE6, 0x30302E)
    /// Nebentexte, Icons.
    static let onSurfaceVariant        = Color.relay(0x68675F, 0xB8B6AC)
    /// Eingabeleiste (dunkler als der Hintergrund).
    static let surfaceContainerLowest  = Color.relay(0xFFFFFF, 0x1F1E1D)
    /// Karten, Dialoge, Blätter.
    static let surfaceContainerLow     = Color.relay(0xF5F3EC, 0x2B2B29)
    /// Tab-Leiste und die Fläche unter der schwebenden Eingabeleiste.
    static let surfaceContainer        = Color.relay(0xF0EEE6, 0x30302E)
    /// Nutzerblase, ungelesene Zeile, Codefeld in Karten.
    static let surfaceContainerHigh    = Color.relay(0xEBE8DF, 0x383836)
    static let surfaceContainerHighest = Color.relay(0xE5E2D8, 0x41413E)
    static let outline                 = Color.relay(0x9B9990, 0x8A887F)
    /// Rahmen von Karten und Eingabeleiste, Trennlinien.
    static let outlineVariant          = Color.relay(0xE2DFD4, 0x3F3E3A)
    /// Rot mit fester Bedeutung: wartet auf dich, Fehler.
    static let error                   = Color.relay(0xB3261E, 0xF2B8B5)
    static let onError                 = Color.relay(0xFFFFFF, 0x601410)
    static let errorContainer          = Color.relay(0xF7DDD8, 0x5C2A27)
    static let onErrorContainer        = Color.relay(0x410E0B, 0xF9DEDC)
    /// Warnstufe 1 (Auslastung hoch) und 2 (fast voll).
    static let levelHigh               = Color.relay(0x8A5E0A, 0xE0A030)
    static let levelCritical           = Color.relay(0xB3261E, 0xFF8A80)
    /// Tönung wartender Karten: errorContainer mit 45 % Deckkraft über dem Hintergrund, deckend gerechnet.
    static let waitingTint             = Color.relay(0xF9ECE8, 0x3E2825)

    /// Farbe zu einer Warnstufe (0 unauffällig, 1 hoch, 2 kritisch).
    static func level(_ level: Int) -> Color {
        level >= 2 ? levelCritical : (level == 1 ? levelHigh : onSurfaceVariant)
    }

    /// Zehn Kreisfarben für Avatare (weiße Schrift), Wahl per Hash des Ordners (RelayCore `Avatars.slot`).
    static let avatarPalette: [Color] = [0xB5543A, 0x5E7F5A, 0x4F6D8A, 0x8A6A3C, 0x7A5C8E,
                                         0x3F7F7A, 0x9A4E6A, 0x6B6B3A, 0x5A6A9A, 0x8A5A4A].map { Color(hex: $0) }
}

/// Schriften. Textstile statt fester Punktgrößen, damit die App mit der Systemschriftgröße mitwächst. In Klammern
/// die Größe des Originals (Material 3) und die Standardgröße des iOS-Stils.
enum RelayFont {
    /// Seitentitel „Heute“ (24, iOS 22), Serif.
    static let headline    = Font.system(.title2, design: .serif, weight: .regular)
    /// Große Namen und Blatt-Titel (22, iOS 20), Serif.
    static let titleLarge  = Font.system(.title3, design: .serif, weight: .regular)
    /// Namen in Listen, Sitzungstitel, Kartentitel (16), Serif, Gewicht Medium.
    static let titleMedium = Font.system(.callout, design: .serif, weight: .medium)
    /// Name auf Karten in „Braucht dich“ (14, iOS 15).
    static let titleSmall  = Font.system(.subheadline, weight: .medium)
    /// Eingabefeld, Fragetext, Optionsbeschriftung (16).
    static let bodyLarge   = Font.system(.callout)
    /// Vorschauzeilen, Leerzustände (14, iOS 15).
    static let bodyMedium  = Font.system(.subheadline)
    /// Banner, Beschreibungen (12).
    static let bodySmall   = Font.system(.caption)
    /// Abschnittstitel in Versalien, Knöpfe (14, iOS 13).
    static let labelLarge  = Font.system(.footnote, weight: .medium)
    /// Alter, Etiketten, Pille (12).
    static let labelMedium = Font.system(.caption, weight: .medium)
    /// Kontext-Etikett, Uhrzeit (11).
    static let labelSmall  = Font.system(.caption2, weight: .medium)
    /// Antworten der Agenten (16), Serif.
    static let reply       = Font.system(.callout, design: .serif)
    /// Befehle, Code, Werkzeugzeilen.
    static let code        = Font.system(.footnote, design: .monospaced)
}

enum RelayRadius {
    static let composer: CGFloat = 26
    static let search: CGFloat = 28
    /// Assistent-Karte, Nutzerblase.
    static let hero: CGFloat = 20
    /// Zeilen, Karten, Wischbänder.
    static let card: CGFloat = 16
    static let thumb: CGFloat = 12
    static let option: CGFloat = 10
    static let chip: CGFloat = 8
    static let tag: CGFloat = 6
}

enum RelaySpace {
    /// Seitenrand für Text.
    static let page: CGFloat = 16
    /// Außenrand von Zeilen und Karten.
    static let rowOuter: CGFloat = 8
    static let sectionTop: CGFloat = 18
    static let sectionBottom: CGFloat = 6
    static let chatGap: CGFloat = 16
    static let cardGap: CGFloat = 6
    static let avatar: CGFloat = 40
    static let avatarRing: CGFloat = 48
    static let barButton: CGFloat = 40
    static let optionMinHeight: CGFloat = 48
    static let pillHeight: CGFloat = 26
}

// MARK: Bausteine

/// Abschnittstitel: Versalien, Akzentfarbe, rechts optional eine Zahl in Rot (nur wenn größer 0).
struct SectionLabel: View {
    let title: String
    var count: Int = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(RelayFont.labelLarge).foregroundStyle(RelayColor.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if count > 0 {
                Text("\(count)").font(RelayFont.labelLarge).foregroundStyle(RelayColor.error)
                    .accessibilityLabel("\(count) offen")
            }
        }
        .padding(.horizontal, RelaySpace.page)
        .padding(.top, RelaySpace.sectionTop)
        .padding(.bottom, RelaySpace.sectionBottom)
    }
}

/// Ruhiger Leerzustand: ein grauer Satz.
struct QuietLine: View {
    let text: String
    var body: some View {
        Text(text).font(RelayFont.bodyMedium).foregroundStyle(RelayColor.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RelaySpace.page).padding(.vertical, 4)
    }
}

/// Kartenfläche mit Radius und optionalem feinem Rahmen.
private struct RelayCardModifier: ViewModifier {
    let fill: Color
    let radius: CGFloat
    let border: Bool

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if border {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(RelayColor.outlineVariant, lineWidth: 1)
                }
            }
    }
}

extension View {
    /// Legt die Ansicht auf eine Kartenfläche (Standard: surfaceContainerLow, Radius 16).
    func relayCard(_ fill: Color = RelayColor.surfaceContainerLow, radius: CGFloat = RelayRadius.card, border: Bool = false) -> some View {
        modifier(RelayCardModifier(fill: fill, radius: radius, border: border))
    }

    /// Seitenhintergrund und Titelzeile im warmen Ton, für die Wurzel eines Tabs und für Unterseiten.
    func relayPage() -> some View {
        background { RelayColor.background.ignoresSafeArea() }
            .toolbarBackground(RelayColor.background, for: .navigationBar)
    }
}

/// Kleine Pille (Höhe 26, voll gerundet), zum Beispiel „3 ungelesen“ oder ein Kontingent.
struct RelayPill: View {
    let text: String
    var fill: Color = RelayColor.secondaryContainer
    var color: Color = RelayColor.onSecondaryContainer

    var body: some View {
        Text(text).font(RelayFont.labelMedium).monospacedDigit().foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: RelaySpace.pillHeight)
            .background(fill, in: Capsule())
    }
}

/// Gefüllter Knopf in Akzentfarbe (erste Option auf einer Karte).
struct RelayFilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RelayFont.labelLarge)
            .foregroundStyle(RelayColor.onPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(RelayColor.primary.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.3), in: Capsule())
    }
}

/// Getönter Knopf (weitere Optionen auf einer Karte).
struct RelayTonalButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RelayFont.labelLarge)
            .foregroundStyle(destructive ? RelayColor.error : RelayColor.onSecondaryContainer)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(RelayColor.secondaryContainer.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .opacity(enabled ? 1 : 0.5)
    }
}

/// Punkt für den Zustand der Verbindung: verbunden Akzent, verbindet Grün, sonst grau oder rot.
struct ConnDot: View {
    // Bewusst kein EnvironmentObject: Der Punkt sitzt in Titelzeilen, dort ist die Umgebung nicht sicher gesetzt.
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        let (color, word): (Color, String) = {
            switch model.state {
            case .connected: return (RelayColor.primary, "Verbunden")
            case .connecting: return (RelayColor.tertiary, "Verbindet")
            case .error: return (RelayColor.error, "Verbindungsfehler")
            default: return (RelayColor.outline, "Nicht verbunden")
            }
        }()
        Circle().fill(color).frame(width: 8, height: 8)
            .frame(width: 24, height: 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(word)
    }
}
