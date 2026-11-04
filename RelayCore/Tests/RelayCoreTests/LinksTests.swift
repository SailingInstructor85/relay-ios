import XCTest
@testable import RelayCore

final class LinksTests: XCTestCase {
    func testExtract() {
        let md = "Siehe [Doku](https://a.example/x) und ![bild](p.png) sowie <https://b.example/y> und https://c.example/z. Noch [lokal](src/a.kt#L42) und [Anker](#oben)."
        let l = Links.extract(md)
        XCTAssertEqual(l.map(\.target), ["https://a.example/x", "https://b.example/y", "https://c.example/z", "src/a.kt#L42"].sorted { md.range(of: $0)!.lowerBound < md.range(of: $1)!.lowerBound })
        XCTAssertEqual(l.first?.label, "Doku")
    }

    func testDistinctAndTrim() {
        XCTAssertEqual(Links.extract("https://example.com/a, https://example.com/a").count, 1)
        XCTAssertEqual(Links.trimUrl("https://x.org/a_(b))."), "https://x.org/a_(b)")
        XCTAssertEqual(Links.extract("www.example.org!").map(\.target), ["www.example.org"])
    }

    func testResolve() {
        XCTAssertEqual(LinkTargets.resolve("https://x.org"), .web("https://x.org"))
        XCTAssertEqual(LinkTargets.resolve("www.x.org"), .web("https://www.x.org"))
        XCTAssertEqual(LinkTargets.resolve("src/a.kt#L42", base: "/home/m/proj"), .file("/home/m/proj/src/a.kt", line: 42))
        XCTAssertEqual(LinkTargets.resolve("a.kt:12:3", base: "/home/m/proj"), .file("/home/m/proj/a.kt", line: 12))
        XCTAssertEqual(LinkTargets.resolve("~/x/y.md", base: "/home/m/proj"), .file("/home/m/x/y.md", line: nil))
        XCTAssertEqual(LinkTargets.resolve("../o/z.txt", base: "/home/m/proj"), .file("/home/m/o/z.txt", line: nil))
        XCTAssertEqual(LinkTargets.resolve("file:///tmp/a%20b.txt"), .file("/tmp/a b.txt", line: nil))
        XCTAssertEqual(LinkTargets.resolve("mailto:a@b.de"), .other("mailto:a@b.de"))
        XCTAssertEqual(LinkTargets.resolve("#abschnitt"), .none)
        XCTAssertEqual(LinkTargets.resolve("<https://x.org>"), .web("https://x.org"))
    }

    func testDecode() {
        XCTAssertEqual(LinkTargets.decode("a%C3%A4b%41"), "aäbA")
        XCTAssertEqual(LinkTargets.decode("100%"), "100%")
    }

    func testFileKinds() {
        XCTAssertEqual(FileKinds.mode("README.md"), .markdown)
        XCTAssertEqual(FileKinds.mode("a.svg"), .text)
        XCTAssertEqual(FileKinds.mode("a.HEIC"), .image)
        XCTAssertEqual(FileKinds.mode("x", kind: "pdf"), .pdf)
        XCTAssertEqual(FileKinds.mode("Makefile"), .text)
        XCTAssertEqual(FileKinds.mode("a.zip"), .other)
        XCTAssertEqual(FileKinds.icon("a.py"), .code)
        XCTAssertEqual(FileKinds.icon("a.mp3"), .audio)
        XCTAssertEqual(FileKinds.mime("a.png"), "image/png")
        XCTAssertEqual(FileKinds.mime("a.rs", mime: "application/octet-stream"), "text/plain")
        XCTAssertEqual(FileKinds.kindOf("a.jpg"), "image")
        XCTAssertEqual(FileKinds.safeName("../a:b/c?.txt"), "c_.txt")
        XCTAssertEqual(FileKinds.sizeLabel(1536), "2 KB")
        XCTAssertEqual(FileKinds.sizeLabel(-1), "")
    }

    func testToolPaths() {
        XCTAssertEqual(ToolPaths.short("/home/m/a/b"), "~/a/b")
        let s = ToolPaths.split(summary: "/home/m/a/b.txt", path: "/home/m/a/b.txt")
        XCTAssertEqual(s.name, "b.txt"); XCTAssertEqual(s.rest, "~/a")
        XCTAssertEqual(ToolPaths.split(summary: "Zeilen 1-20", path: "/x/y").rest, "Zeilen 1-20")
    }

    func testMarkdownBlocks() {
        let md = "# Titel\n\nText eins\nText zwei\n\n- a\n  - b\n1. eins\n- [x] fertig\n\n> zitat\n\n---\n\n```swift\nlet x = 1\n```\n\n| A | B |\n|---|--:|\n| 1 | 2 |\n"
        let b = MdBlocks.parse(md)
        XCTAssertEqual(b[0], .heading(level: 1, text: "Titel"))
        XCTAssertEqual(b[1], .paragraph("Text eins\nText zwei"))
        XCTAssertEqual(b[2], .item(indent: 0, number: nil, checked: nil, text: "a"))
        XCTAssertEqual(b[3], .item(indent: 1, number: nil, checked: nil, text: "b"))
        XCTAssertEqual(b[4], .item(indent: 0, number: 1, checked: nil, text: "eins"))
        XCTAssertEqual(b[5], .item(indent: 0, number: nil, checked: true, text: "fertig"))
        XCTAssertEqual(b[6], .quote("zitat"))
        XCTAssertEqual(b[7], .rule)
        XCTAssertEqual(b[8], .code(lang: "swift", text: "let x = 1"))
        XCTAssertEqual(b[9], .table(header: ["A", "B"], rows: [["1", "2"]], rightAligned: [false, true]))
    }

    func testTableCellsEscape() {
        XCTAssertEqual(MdBlocks.cells("| a \\| b | c |"), ["a | b", "c"])
    }
}
