import Foundation

/// Block-level parts of a chat message (port of Android MdBlocks / ChatText).
public enum MdBlock: Sendable, Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    /// `marker` nil = bullet, else the ordered number; `box` nil = no task box, else checked or not.
    case item(indent: Int, number: Int?, checked: Bool?, text: String)
    case quote(String)
    case rule
    case code(lang: String, text: String)
    case table(header: [String], rows: [[String]], rightAligned: [Bool])
}

public enum MdBlocks {
    private static let fence = Rx.make("^\\s{0,3}(`{3,}(?=[^`]*$)|~{3,})\\s*([\\w+#.-]*)")
    private static let sepRow = Rx.make("^\\s*\\|?\\s*:?-{1,}:?\\s*(\\|\\s*:?-{1,}:?\\s*)*\\|?\\s*$")
    private static let headingRx = Rx.make("^\\s{0,3}(#{1,6})\\s+(.*?)\\s*#*\\s*$")
    private static let ruleRx = Rx.make("^\\s{0,3}([-*_])(\\s*\\1){2,}\\s*$")
    private static let itemRx = Rx.make("^(\\s*)([-*+]|\\d{1,9}[.)])\\s+(?:\\[([ xX])\\]\\s+)?(.*)$")

    /// Splits a message into blocks. Consecutive plain lines form one paragraph.
    public static func parse(_ md: String) -> [MdBlock] {
        var out: [MdBlock] = []
        var para: [String] = []
        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] }
        }
        let lines = md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if let f = Rx.matches(fence, line).first {
                flush()
                let mark = Rx.group(f, 1, in: line)
                let indent = line.count - String(line.drop(while: { $0 == " " || $0 == "\t" })).count
                var body: [String] = []
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(mark) && t.allSatisfy({ $0 == mark.first! }) { break }
                    let l = lines[i]
                    let lead = l.count - String(l.drop(while: { $0 == " " || $0 == "\t" })).count
                    body.append(String(l.dropFirst(min(indent, lead))))
                    i += 1
                }
                i += 1
                out.append(.code(lang: Rx.group(f, 2, in: line), text: body.joined(separator: "\n")))
                continue
            }
            if line.contains("|"), i + 1 < lines.count, lines[i + 1].contains("-"), Rx.fullMatch(sepRow, lines[i + 1]) {
                let header = cells(line), seps = cells(lines[i + 1])
                if header.count >= 2 && seps.count == header.count {
                    flush()
                    var rows: [[String]] = []
                    i += 2
                    while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        let r = cells(lines[i])
                        rows.append((0..<header.count).map { r.indices.contains($0) ? r[$0] : "" })
                        i += 1
                    }
                    out.append(.table(header: header, rows: rows, rightAligned: seps.map { $0.hasSuffix(":") && !$0.hasPrefix(":") }))
                    continue
                }
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush(); i += 1; continue }
            if let m = Rx.matches(headingRx, line).first {
                flush()
                out.append(.heading(level: Rx.group(m, 1, in: line).count, text: Rx.group(m, 2, in: line)))
                i += 1; continue
            }
            if Rx.fullMatch(ruleRx, line) { flush(); out.append(.rule); i += 1; continue }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                flush()
                var q: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var t = lines[i].trimmingCharacters(in: .whitespaces)
                    t.removeFirst()
                    if t.hasPrefix(" ") { t.removeFirst() }
                    q.append(t); i += 1
                }
                out.append(.quote(q.joined(separator: "\n")))
                continue
            }
            if let m = Rx.matches(itemRx, line).first {
                flush()
                let marker = Rx.group(m, 2, in: line)
                let box = Rx.group(m, 3, in: line)
                let num = marker.first!.isNumber ? Int(marker.dropLast()) : nil
                out.append(.item(indent: Rx.group(m, 1, in: line).count / 2, number: num,
                                 checked: box.isEmpty ? nil : (box != " "), text: Rx.group(m, 4, in: line)))
                i += 1; continue
            }
            para.append(line); i += 1
        }
        flush()
        return out
    }

    /// Cells of one table row; `\|` stays inside a cell.
    public static func cells(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") && !s.hasSuffix("\\|") { s.removeLast() }
        var out: [String] = []
        var cur = ""
        let ch = Array(s)
        var k = 0
        while k < ch.count {
            if ch[k] == "\\", k + 1 < ch.count, ch[k + 1] == "|" { cur.append("|"); k += 2; continue }
            if ch[k] == "|" { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" } else { cur.append(ch[k]) }
            k += 1
        }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        return out
    }
}
