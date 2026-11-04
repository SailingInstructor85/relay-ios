import SwiftUI
import RelayCore

/// Hooks the chat gives to message rows (open a file, open the message menu).
struct ChatActions {
    var openPath: (String) -> Void = { _ in }
    var openFile: (RemoteRef) -> Void = { _ in }
    var menu: (TMessage) -> Void = { _ in }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MdBlocks.parse(text).enumerated()), id: \.offset) { _, b in block(b) }
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

    private func marker(number: Int?, checked: Bool?) -> String {
        if let c = checked { return c ? "☑" : "☐" }
        if let n = number { return "\(n)." }
        return "•"
    }

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
