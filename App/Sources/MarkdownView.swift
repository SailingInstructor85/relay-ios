import SwiftUI
import RelayCore

/// Hooks the chat gives to message rows (open a file, open the message menu).
struct ChatActions {
    var openPath: (String) -> Void = { _ in }
    var openFile: (RemoteRef) -> Void = { _ in }
    var menu: (TMessage) -> Void = { _ in }
    /// Reads a text aloud (the small speaker under an answer).
    var speak: (String) -> Void = { _ in }
}

private struct ChatActionsKey: EnvironmentKey { static let defaultValue = ChatActions() }
extension EnvironmentValues {
    var chatActions: ChatActions {
        get { self[ChatActionsKey.self] }
        set { self[ChatActionsKey.self] = newValue }
    }
}

/// Routes a tapped link: web and other schemes to iOS, files through `file_info` to the viewer.
@MainActor
enum LinkRouter {
    static func open(_ raw: String, base: String?, onFile: @escaping (RemoteRef) -> Void, onError: @escaping (String) -> Void = { _ in }) {
        switch LinkTargets.resolve(raw, base: base) {
        case .web(let u), .other(let u):
            if let url = URL(string: u) { UIApplication.shared.open(url) }
        case .file(let path, _):
            Task {
                do { onFile(try await FileStore.shared.info(path)) }
                catch { onError(error.localizedDescription) }
            }
        case .none: break
        }
    }
}

/// Markdown for chat messages: headings, lists, quotes, rules, code blocks and tables as blocks, inline marks and
/// links inside (links open through the environment's `openURL`).
struct MarkdownText: View {
    let text: String
    var selectable = true
    /// Text per langem Drücken markieren (Griffe, Teile kopieren) statt nur das Kopieren-Pop-up für den ganzen Absatz:
    /// Fließtext läuft dann über `SelectableBlocks` (UITextView). Genutzt im Jarvis-Chat.
    var marking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if marking {
                ForEach(Array(MdBlocks.runs(MdBlocks.parse(text)).enumerated()), id: \.offset) { _, r in
                    switch r {
                    case .text(let blocks): SelectableBlocks(blocks: blocks)
                    case .block(let b): block(b)
                    }
                }
            } else {
                ForEach(Array(MdBlocks.parse(text).enumerated()), id: \.offset) { _, b in block(b) }
            }
        }
    }

    @ViewBuilder private func block(_ b: MdBlock) -> some View {
        switch b {
        case .paragraph(let t):
            rich(Self.inline(t))
        case .heading(let level, let t):
            rich(Self.inline(t)).font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold()).padding(.top, 4)
        case .item(let indent, let number, let checked, let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker(number: number, checked: checked)).foregroundStyle(.secondary).frame(minWidth: 16, alignment: .trailing)
                rich(Self.inline(t))
            }.padding(.leading, CGFloat(indent) * 14)
        case .quote(let t):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.5)).frame(width: 3)
                rich(Self.inline(t)).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        case .rule:
            Divider().padding(.vertical, 2)
        case .code(_, let t):
            CodeBlock(text: t, selectable: selectable)
        case .table(let header, let rows, let right):
            TableBlock(header: header, rows: rows, right: right)
        }
    }

    @ViewBuilder private func rich(_ a: AttributedString) -> some View {
        if selectable { Text(a).textSelection(.enabled) } else { Text(a) }
    }

    private func marker(number: Int?, checked: Bool?) -> String { MdBlocks.marker(number: number, checked: checked) }

    /// Inline markdown with bare URLs made tappable.
    static func inline(_ s: String) -> AttributedString {
        let a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        return linkified(a)
    }

    /// Makes bare http(s) and www. URLs of an attributed text tappable (not inside code spans or existing links).
    static func linkified(_ attr: AttributedString) -> AttributedString {
        var out = attr
        let s = String(attr.characters)
        for u in Links.bareUrls(s) {
            let raw = u.url.lowercased().hasPrefix("www.") ? "https://" + u.url : u.url
            guard let url = URL(string: raw), u.start >= 0, u.end <= s.utf16.count else { continue }
            let a = String.Index(utf16Offset: u.start, in: s), b = String.Index(utf16Offset: u.end, in: s)
            let lo = out.index(out.startIndex, offsetByCharacters: s.distance(from: s.startIndex, to: a))
            let hi = out.index(out.startIndex, offsetByCharacters: s.distance(from: s.startIndex, to: b))
            guard lo < hi else { continue }
            if out[lo..<hi].runs.contains(where: { $0.link != nil || $0.inlinePresentationIntent?.contains(.code) == true }) { continue }
            out[lo..<hi].link = url
        }
        return out
    }
}

/// Fließtext einer Antwort als ein Stück, in dem sich per langem Drücken Text markieren lässt (UITextView, nicht
/// editierbar, ohne eigenes Scrollen). SwiftUI-`Text` mit `textSelection` kann auf dem iPhone nur den ganzen Text
/// kopieren. Überschriften, Listen und Zitate werden als Absatzformate gesetzt, Links bleiben tippbar.
/// Schrift wie `RelayFont.reply` (Serif, Textstil callout), sie wächst mit der Systemschriftgröße.
struct SelectableBlocks: UIViewRepresentable {
    let blocks: [MdBlock]

    final class Coordinator {
        var blocks: [MdBlock] = []
        var size: DynamicTypeSize?
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
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.required, for: .vertical)
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        let c = context.coordinator
        let size = context.environment.dynamicTypeSize
        // nur bei neuem Inhalt setzen, sonst ginge eine laufende Markierung verloren
        guard c.blocks != blocks || c.size != size else { return }
        c.blocks = blocks
        c.size = size
        v.attributedText = Self.attributed(blocks)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        var width = (uiView.window?.windowScene?.screen.bounds.width ?? 393) - 32
        if let w = proposal.width, w.isFinite, w > 0 { width = w }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }

    // MARK: Text aufbauen

    private static func baseFont() -> UIFont {
        let d = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .callout)
        return UIFont(descriptor: d.withDesign(.serif) ?? d, size: 0)
    }

    private static func variant(_ font: UIFont, bold: Bool, italic: Bool, scale: CGFloat = 1) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let d = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
        return UIFont(descriptor: d, size: font.pointSize * scale)
    }

    static func attributed(_ blocks: [MdBlock]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let base = baseFont()
        for (i, b) in blocks.enumerated() {
            let last = i == blocks.count - 1
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 3
            para.paragraphSpacing = last ? 0 : 6
            var font = base
            var color = UIColor.label
            var prefix = ""
            let text: String
            switch b {
            case .paragraph(let t):
                text = t
            case .heading(let level, let t):
                text = t
                font = variant(base, bold: true, italic: false, scale: level == 1 ? 1.25 : level == 2 ? 1.1 : 1)
                if i > 0 { para.paragraphSpacingBefore = 4 }
            case .item(let indent, let number, let checked, let t):
                text = t
                prefix = MdBlocks.marker(number: number, checked: checked) + "\t"
                let lead = CGFloat(indent) * 14
                para.firstLineHeadIndent = lead
                para.headIndent = lead + 22
                para.tabStops = [NSTextTab(textAlignment: .left, location: lead + 22, options: [:])]
                para.defaultTabInterval = 22
            case .quote(let t):
                text = t
                color = .secondaryLabel
                para.firstLineHeadIndent = 11
                para.headIndent = 11
            case .rule, .code, .table:
                continue  // stehen als eigene Blöcke zwischen den Textstücken (MdBlocks.runs)
            }
            if !prefix.isEmpty {
                out.append(NSAttributedString(string: prefix, attributes: [.font: base, .foregroundColor: UIColor.secondaryLabel, .paragraphStyle: para]))
            }
            let inline = MarkdownText.inline(text)
            for run in inline.runs {
                let intent = run.inlinePresentationIntent ?? []
                var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color, .paragraphStyle: para]
                if intent.contains(.code) {
                    attrs[.font] = UIFont.monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular)
                } else {
                    attrs[.font] = variant(font, bold: intent.contains(.stronglyEmphasized), italic: intent.contains(.emphasized))
                }
                if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let url = run.link { attrs[.link] = url }
                out.append(NSAttributedString(string: String(inline[run.range].characters), attributes: attrs))
            }
            if !last { out.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: para])) }
        }
        return out
    }
}

struct CodeBlock: View {
    let text: String
    var selectable = true
    @State private var copied = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if selectable { Text(text).textSelection(.enabled) } else { Text(text) }
            }
            .font(.system(.caption, design: .monospaced)).padding(8).padding(.trailing, 26)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            Button {
                UIPasteboard.general.string = text
                copied = true
                Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption2).padding(6)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Code kopieren")
        }
    }
}

struct TableBlock: View {
    let header: [String]
    let rows: [[String]]
    let right: [Bool]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { i, h in
                        cell(h).font(.footnote.bold()).gridColumnAlignment(right.indices.contains(i) && right[i] ? .trailing : .leading)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    GridRow {
                        ForEach(Array(r.enumerated()), id: \.offset) { _, c in cell(c).font(.footnote) }
                    }
                }
            }
            .padding(8)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cell(_ s: String) -> some View {
        Text(MarkdownText.inline(s)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 260, alignment: .leading)
    }
}
