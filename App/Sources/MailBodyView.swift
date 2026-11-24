import SwiftUI
import UIKit
import RelayCore

/// Der Text einer Mail als ein Stück, in dem sich per langem Drücken einzelne Wörter und Stellen markieren und
/// kopieren lassen (UITextView wie im Jarvis-Chat, nicht editierbar, ohne eigenes Scrollen). Links stehen in der
/// Akzentfarbe und unterstrichen. Der Text ist fremd: Die Ansicht öffnet selbst nichts und lädt keine Vorschau.
/// Ein Tipp auf einen Link meldet `onTap`, langes Drücken `onHold`; was dann geschieht, entscheidet `MailView`.
struct MailBodyText: UIViewRepresentable {
    let text: String
    let links: [MailLink]
    var onTap: (MailLink) -> Void
    var onHold: (MailLink) -> Void

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: String?
        var size: DynamicTypeSize?
        var links: [MailLink] = []
        var onTap: (MailLink) -> Void = { _ in }
        var onHold: (MailLink) -> Void = { _ in }

        /// iOS fragt vor jeder Aktion an einem Link. Die Antwort ist immer nein: kein Öffnen durch das System, keine
        /// Seitenvorschau. Tippen und langes Drücken gehen an die Mailansicht.
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange,
                      interaction: UITextItemInteraction) -> Bool {
            let at = characterRange.location
            guard let link = links.first(where: { $0.start <= at && at < $0.end }) else { return false }
            if interaction == .invokeDefaultAction { onTap(link) } else { onHold(link) }
            return false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.isScrollEnabled = false
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.dataDetectorTypes = []
        v.linkTextAttributes = [
            .foregroundColor: UIColor(RelayColor.primary),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        v.delegate = context.coordinator
        v.accessibilityIdentifier = "mailBody"
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.required, for: .vertical)
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        let c = context.coordinator
        c.onTap = onTap
        c.onHold = onHold
        let size = context.environment.dynamicTypeSize
        // nur bei neuem Inhalt setzen, sonst ginge eine laufende Markierung verloren
        guard c.text != text || c.size != size else { return }
        c.text = text
        c.size = size
        c.links = links
        v.attributedText = Self.attributed(text, links: links)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        var width = (uiView.window?.windowScene?.screen.bounds.width ?? 393) - 32
        if let w = proposal.width, w.isFinite, w > 0 { width = w }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }

    /// Die Adresse eines Links für iOS, nil wenn sie sich nicht bilden lässt oder nicht erlaubt ist.
    static func url(_ link: MailLink) -> URL? {
        guard MailLinks.allowed(link.target) else { return nil }
        if let u = URL(string: link.target) { return u }
        return link.target.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap { URL(string: $0) }
    }

    static func attributed(_ text: String, links: [MailLink]) -> NSAttributedString {
        let d = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .callout)
        let font = UIFont(descriptor: d.withDesign(.serif) ?? d, size: 0)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let out = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: UIColor.label, .paragraphStyle: para,
        ])
        for link in links {
            guard link.start >= 0, link.end > link.start, link.end <= out.length, let url = url(link) else { continue }
            out.addAttribute(.link, value: url, range: NSRange(location: link.start, length: link.end - link.start))
        }
        return out
    }
}
