import Foundation

/// Writes a web article as a minimal EPUB 3 (one chapter, one nav) so it travels the same
/// reflowable path as a book (spec §2.1). The original HTML is retained by `Library`, not here.
public enum ArticleEPUBWriter {
    public static let chapterHref = "OEBPS/article.xhtml"
    static let opfHref = "OEBPS/content.opf"
    static let navHref = "OEBPS/nav.xhtml"

    /// The whole EPUB as bytes. Throws `ImportError.malformedBody` or `ImportError.noText`.
    public static func epub(for article: ArticleContent, identifier: UUID = UUID(), modified: Date = Date()) throws -> Data {
        let text = try XHTML.plainText(ofFragment: article.bodyXHTML)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.noText }
        return StoredZipWriter.archive([
            ZipEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
            ZipEntry(name: "META-INF/container.xml", data: Data(container.utf8)),
            ZipEntry(name: opfHref, data: Data(opf(for: article, identifier: identifier, modified: modified).utf8)),
            ZipEntry(name: navHref, data: Data(nav(for: article).utf8)),
            ZipEntry(name: chapterHref, data: Data(chapter(for: article).utf8)),
        ])
    }

    public static func write(_ article: ArticleContent, to url: URL, identifier: UUID = UUID(), modified: Date = Date()) throws {
        try epub(for: article, identifier: identifier, modified: modified).write(to: url, options: .atomic)
    }

    static let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>

        """

    static func opf(for a: ArticleContent, identifier: UUID, modified: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        var meta: [String] = [
            "<dc:identifier id=\"pub-id\">urn:uuid:\(identifier.uuidString.lowercased())</dc:identifier>",
            "<dc:title>\(XHTML.escape(a.title))</dc:title>",
            "<dc:language>\(XHTML.escape(a.language))</dc:language>",
        ]
        if let byline = a.byline { meta.append("<dc:creator>\(XHTML.escape(byline))</dc:creator>") }
        if let site = a.siteName { meta.append("<dc:publisher>\(XHTML.escape(site))</dc:publisher>") }
        if let url = a.sourceURL { meta.append("<dc:source>\(XHTML.escape(url.absoluteString))</dc:source>") }
        if let excerpt = a.excerpt { meta.append("<dc:description>\(XHTML.escape(excerpt))</dc:description>") }
        meta.append("<meta property=\"dcterms:modified\">\(formatter.string(from: modified))</meta>")
        let metadata = meta.map { "    " + $0 }.joined(separator: "\n")
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id" xml:lang="\(XHTML.escape(a.language))">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            \(metadata)
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="article" href="article.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="article"/>
              </spine>
            </package>

            """
    }

    static func nav(for a: ArticleContent) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
          <head><title>Contents</title></head>
          <body>
            <nav epub:type="toc">
              <h1>Contents</h1>
              <ol><li><a href="article.xhtml">\(XHTML.escape(a.title))</a></li></ol>
            </nav>
          </body>
        </html>

        """
    }

    static func chapter(for a: ArticleContent) -> String {
        let lang = XHTML.escape(a.language)
        let byline = a.byline.map { "      <p class=\"byline\">\(XHTML.escape($0))</p>\n" } ?? ""
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(lang)" lang="\(lang)">
              <head>
                <meta charset="utf-8"/>
                <title>\(XHTML.escape(a.title))</title>
              </head>
              <body>
                <section epub:type="bodymatter chapter">
                  <h1>\(XHTML.escape(a.title))</h1>
            \(byline)      <div class="article-body">
            \(a.bodyXHTML)
                  </div>
                </section>
              </body>
            </html>

            """
    }
}
