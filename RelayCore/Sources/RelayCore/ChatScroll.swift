import Foundation

/// Folgt ein Chatverlauf seinem Ende? Solange man unten steht, scrollt der Verlauf bei neuem Inhalt mit (eigene
/// Nachricht, einlaufende Antwort, Diktat). Wer von Hand nach oben scrollt, bleibt dort stehen, und ein runder Knopf
/// mit Pfeil nach unten erscheint („Ans Ende springen“, wie in Messenger-Apps). Die Ansicht meldet jede Bewegung
/// mit `moved`; ob gefolgt wird, hängt allein an der Bewegungsrichtung:
/// - Wächst der Inhalt unten (neue Zeile, Antwort läuft ein), ändert sich die Position nicht: Es wird weiter gefolgt.
/// - Geht die Position nach oben und das Ende ist weiter weg als `tolerance`, hat der Nutzer hochgescrollt.
/// - Steht das Ende wieder im Bild (von Hand oder über den Knopf), wird wieder gefolgt.
public struct ChatScroll: Equatable, Sendable {
    /// So nah am Ende (in Punkten) gilt der Verlauf als „unten“: Ein paar Punkte Spiel fängt Nachfedern und
    /// Rundungen ab, eine Textzeile mehr zählt schon als hochgescrollt.
    public static let tolerance = 48.0
    /// Beschriftung des Knopfs für VoiceOver.
    public static let jumpLabel = "Ans Ende springen"

    /// true: Bei neuem Inhalt scrollt die Ansicht ans Ende.
    public private(set) var follows = true
    private var lastOffset: Double?

    public init() {}

    /// Der Knopf „Ans Ende springen“ ist nur zu sehen, wenn hochgescrollt ist.
    public var showsJump: Bool { !follows }

    /// Abstand des sichtbaren Ausschnitts vom Ende des Inhalts (0 = ganz unten, auch wenn der Inhalt kürzer ist
    /// als der Ausschnitt).
    public static func distance(offset: Double, content: Double, viewport: Double) -> Double {
        max(0, content - offset - viewport)
    }

    /// Eine Bewegung oder Größenänderung. `offset`: wie weit der Inhalt nach oben herausgeschoben ist, `content`:
    /// Höhe des ganzen Inhalts, `viewport`: Höhe des sichtbaren Ausschnitts. Ohne Ausschnitt (noch kein Layout)
    /// geschieht nichts.
    public mutating func moved(offset: Double, content: Double, viewport: Double) {
        guard viewport > 0 else { return }
        defer { lastOffset = offset }
        if Self.distance(offset: offset, content: content, viewport: viewport) <= Self.tolerance {
            follows = true
        } else if let last = lastOffset, offset < last - 1 {
            follows = false
        }
    }

    /// Der Knopf wurde getippt: wieder folgen, die Ansicht scrollt ans Ende.
    public mutating func jump() { follows = true }
}
