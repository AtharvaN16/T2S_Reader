import Foundation
import Testing
@testable import T2SLibrary

@Suite struct ArticleEPUBWriterTests {
    let article = ArticleContent(
        title: "Tom & Jerry <3",
        byline: "Jane Doe",
        siteName: "Example",
        sourceURL: URL(string: "https://example.com/tom?a=1&b=2"),
        bodyXHTML: "<p>First paragraph.</p><p>Second <em>one</em> &amp; more.</p>",
        excerpt: "Cats and mice.")

    @Test func xhtmlHelpers() throws {
        #expect(try XHTML.plainText(ofFragment: article.bodyXHTML) == "First paragraph.Second one & more.")
        #expect(throws: ImportError.self) { try XHTML.validateFragment("<p>unclosed") }
        #expect(throws: ImportError.self) { try XHTML.validateFragment("<p>&nbsp;</p>") }   // HTML entity, not XML
        try XHTML.validateFragment("<p>a\u{00A0}b<br/>c</p>")
        #expect(XHTML.escape("a & b < c > \"d\"") == "a &amp; b &lt; c &gt; &quot;d&quot;")
    }

    @Test func writesAValidContainer() throws {
        let epub = try ArticleEPUBWriter.epub(
            for: article,
            identifier: UUID(uuidString: "0C1A9E2E-6D2B-4A8C-9F0D-1B2C3D4E5F60")!,
            modified: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(epub.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(epub[30..<38] == Data("mimetype".utf8))                    // first, stored, no extra field
        #expect(epub[38..<58] == Data("application/epub+zip".utf8))
        #if os(macOS)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-epub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.epub")
        try epub.write(to: url)
        let unzip = try Shell.run("/usr/bin/unzip", ["-o", "-q", url.path, "-d", dir.path])
        #expect(unzip.status == 0, "\(unzip.output)")

        let container = try String(contentsOf: dir.appendingPathComponent("META-INF/container.xml"), encoding: .utf8)
        #expect(container.contains("full-path=\"OEBPS/content.opf\""))
        let opf = try String(contentsOf: dir.appendingPathComponent("OEBPS/content.opf"), encoding: .utf8)
        #expect(opf.contains("<dc:title>Tom &amp; Jerry &lt;3</dc:title>"))
        #expect(opf.contains("<dc:identifier id=\"pub-id\">urn:uuid:0c1a9e2e-6d2b-4a8c-9f0d-1b2c3d4e5f60</dc:identifier>"))
        #expect(opf.contains("<dc:creator>Jane Doe</dc:creator>"))
        #expect(opf.contains("<dc:publisher>Example</dc:publisher>"))
        #expect(opf.contains("<dc:source>https://example.com/tom?a=1&amp;b=2</dc:source>"))
        #expect(opf.contains("<dc:description>Cats and mice.</dc:description>"))
        #expect(opf.contains("<meta property=\"dcterms:modified\">2023-11-14T22:13:20Z</meta>"))
        #expect(opf.contains("properties=\"nav\""))
        #expect(opf.contains("<itemref idref=\"article\"/>"))
        let chapter = try String(contentsOf: dir.appendingPathComponent(ArticleEPUBWriter.chapterHref), encoding: .utf8)
        let text = try XHTML.plainText(ofDocument: chapter)
        #expect(text.contains("Tom & Jerry <3"))
        #expect(text.contains("First paragraph."))
        #expect(chapter.contains("<p class=\"byline\">Jane Doe</p>"))
        let nav = try String(contentsOf: dir.appendingPathComponent("OEBPS/nav.xhtml"), encoding: .utf8)
        #expect(nav.contains("epub:type=\"toc\""))
        #expect(nav.contains("<a href=\"article.xhtml\">Tom &amp; Jerry &lt;3</a>"))
        for name in ["OEBPS/nav.xhtml", "OEBPS/content.opf", "META-INF/container.xml"] {
            let xml = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            _ = try XHTML.plainText(ofDocument: xml)                     // well-formed
        }
        #endif
    }

    @Test func optionalMetadataIsOmittedNotEmptied() throws {
        let bare = ArticleContent(title: "Bare", bodyXHTML: "<p>Text.</p>")
        let epub = try ArticleEPUBWriter.epub(for: bare)
        let opf = try #require(String(data: epub, encoding: .isoLatin1))   // stored entries are readable in place
        #expect(!opf.contains("<dc:creator>"))
        #expect(!opf.contains("<dc:source>"))
        #expect(!opf.contains("<dc:publisher>"))
        #expect(!opf.contains("class=\"byline\""))
        #expect(opf.contains("<dc:language>en</dc:language>"))
    }

    @Test func malformedBodyIsRejectedBeforeWriting() {
        var bad = article
        bad.bodyXHTML = "<p>unclosed"
        #expect(throws: ImportError.self) { try ArticleEPUBWriter.epub(for: bad) }
    }

    @Test func scriptsAndHandlersAreRejected() throws {
        #expect(throws: ImportError.self) { try XHTML.validateFragment("<p onclick=\"x()\">a</p>") }
        #expect(throws: ImportError.self) { try XHTML.validateFragment("<script>1</script>") }
        #expect(throws: ImportError.self) { try XHTML.validateFragment("<a href=\"javascript:alert(1)\">x</a>") }
        try XHTML.validateFragment("<section epub:type=\"chapter\"><p>ok</p></section>")
    }

    @Test func emptyBodyIsRejected() {
        var empty = article
        empty.bodyXHTML = "<div> \n </div>"
        #expect(throws: ImportError.noText) { try ArticleEPUBWriter.epub(for: empty) }
    }
}
