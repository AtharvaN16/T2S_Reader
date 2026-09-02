import Foundation
import T2SLibrary

enum EPUBFixture {
    static func xhtml(title: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(title)</title></head><body>\(body)</body></html>
        """
    }

    static let front = xhtml(title: "Front", body: "<h1>Title Page</h1><p>By Someone.</p>")
    static let ch1 = xhtml(title: "One", body: "<h1>Chapter One</h1><p>First paragraph of one.</p><p>Second paragraph of one.</p>")
    static let ch2 = xhtml(title: "Two", body: "<h1>Chapter Two</h1><p>Only paragraph of two.</p>")
    static let blank = xhtml(title: "Blank", body: "")

    static func opf(spine: [String]) -> String {
        let items = spine.map { "<item id=\"\($0.replacingOccurrences(of: ".xhtml", with: ""))\" href=\"\($0)\" media-type=\"application/xhtml+xml\"/>" }
        let refs = spine.map { "<itemref idref=\"\($0.replacingOccurrences(of: ".xhtml", with: ""))\"/>" }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="pub-id">urn:uuid:5f1a2b3c-0000-4000-8000-000000000001</dc:identifier>
            <dc:title>Fixture Book</dc:title>
            <dc:creator>Ada Author</dc:creator>
            <dc:language>en</dc:language>
            <meta property="dcterms:modified">2026-09-02T00:00:00Z</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            \(items.joined(separator: "\n    "))
          </manifest>
          <spine>\(refs.joined())</spine>
        </package>
        """
    }

    static func nav(_ entries: [(title: String, href: String)]) -> String {
        let items = entries.map { "<li><a href=\"\($0.href)\">\($0.title)</a></li>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>
        <body><nav epub:type="toc"><ol>\(items)</ol></nav></body></html>
        """
    }

    static let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """

    static let adeptEncryption = """
        <?xml version="1.0"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#" xmlns:sig="http://www.w3.org/2000/09/xmldsig#" xmlns:adept="http://ns.adobe.com/adept">
          <enc:EncryptedData>
            <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
            <sig:KeyInfo><adept:resource>urn:uuid:5f1a2b3c-0000-4000-8000-000000000001</adept:resource></sig:KeyInfo>
            <enc:CipherData><enc:CipherReference URI="OEBPS/ch1.xhtml"/></enc:CipherData>
          </enc:EncryptedData>
        </encryption>
        """

    static func write(_ entries: [ZipEntry], name: String = "book.epub") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-epub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        let all = [ZipEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
                   ZipEntry(name: "META-INF/container.xml", data: Data(container.utf8))] + entries
        try StoredZipWriter.archive(all).write(to: url)
        return url
    }

    /// front.xhtml (not in the TOC), ch1, ch2, and a blank spine item; TOC → ch1, ch2.
    static func twoChapterBook() throws -> URL {
        try write([
            ZipEntry(name: "OEBPS/content.opf", data: Data(opf(spine: ["front.xhtml", "ch1.xhtml", "ch2.xhtml", "blank.xhtml"]).utf8)),
            ZipEntry(name: "OEBPS/nav.xhtml", data: Data(nav([("Chapter One", "ch1.xhtml"), ("Chapter Two", "ch2.xhtml")]).utf8)),
            ZipEntry(name: "OEBPS/front.xhtml", data: Data(front.utf8)),
            ZipEntry(name: "OEBPS/ch1.xhtml", data: Data(ch1.utf8)),
            ZipEntry(name: "OEBPS/ch2.xhtml", data: Data(ch2.utf8)),
            ZipEntry(name: "OEBPS/blank.xhtml", data: Data(blank.utf8)),
        ])
    }

    /// One chapter, no TOC entries.
    static func noTOCBook() throws -> URL {
        try write([
            ZipEntry(name: "OEBPS/content.opf", data: Data(opf(spine: ["ch1.xhtml", "ch2.xhtml"]).utf8)),
            ZipEntry(name: "OEBPS/nav.xhtml", data: Data(nav([]).utf8)),
            ZipEntry(name: "OEBPS/ch1.xhtml", data: Data(ch1.utf8)),
            ZipEntry(name: "OEBPS/ch2.xhtml", data: Data(ch2.utf8)),
        ])
    }

    static func drmBook() throws -> URL {
        try write([
            ZipEntry(name: "META-INF/encryption.xml", data: Data(adeptEncryption.utf8)),
            ZipEntry(name: "OEBPS/content.opf", data: Data(opf(spine: ["ch1.xhtml"]).utf8)),
            ZipEntry(name: "OEBPS/nav.xhtml", data: Data(nav([("Chapter One", "ch1.xhtml")]).utf8)),
            ZipEntry(name: "OEBPS/ch1.xhtml", data: Data(ch1.utf8)),
        ])
    }

    static let percentEncodedOPF = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="pub-id">urn:uuid:5f1a2b3c-0000-4000-8000-000000000002</dc:identifier>
            <dc:title>Fixture Book</dc:title>
            <dc:creator>Ada Author</dc:creator>
            <dc:language>en</dc:language>
            <meta property="dcterms:modified">2026-09-02T00:00:00Z</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="ch1" href="ch%201.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="ch1"/><itemref idref="ch2"/></spine>
        </package>
        """

    /// ch1's manifest href is percent-encoded (`ch%201.xhtml`) and resolves to an entry stored under
    /// a literal space (`OEBPS/ch 1.xhtml`) — Readium may report this href differently between the
    /// reading order and content locators, which must not cause a false "skipped" resource.
    static func percentEncodedHrefBook() throws -> URL {
        try write([
            ZipEntry(name: "OEBPS/content.opf", data: Data(percentEncodedOPF.utf8)),
            ZipEntry(name: "OEBPS/nav.xhtml", data: Data(nav([("Chapter One", "ch%201.xhtml"), ("Chapter Two", "ch2.xhtml")]).utf8)),
            ZipEntry(name: "OEBPS/ch 1.xhtml", data: Data(ch1.utf8)),
            ZipEntry(name: "OEBPS/ch2.xhtml", data: Data(ch2.utf8)),
        ])
    }

    static let nestedNav = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>
        <body><nav epub:type="toc"><ol><li><a href="ch1.xhtml">Part</a><ol><li><a href="ch1.xhtml">Chapter One</a></li></ol></li><li><a href="ch2.xhtml#start">Chapter Two</a></li></ol></nav></body></html>
        """

    /// front/ch1/ch2 spine; TOC has a parent entry and a nested child both pointing at ch1.xhtml
    /// (first title wins), and a final entry pointing at ch2.xhtml with a `#fragment`.
    static func nestedTOCBook() throws -> URL {
        try write([
            ZipEntry(name: "OEBPS/content.opf", data: Data(opf(spine: ["front.xhtml", "ch1.xhtml", "ch2.xhtml"]).utf8)),
            ZipEntry(name: "OEBPS/nav.xhtml", data: Data(nestedNav.utf8)),
            ZipEntry(name: "OEBPS/front.xhtml", data: Data(front.utf8)),
            ZipEntry(name: "OEBPS/ch1.xhtml", data: Data(ch1.utf8)),
            ZipEntry(name: "OEBPS/ch2.xhtml", data: Data(ch2.utf8)),
        ])
    }
}
