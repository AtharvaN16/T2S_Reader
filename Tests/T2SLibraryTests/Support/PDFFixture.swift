import CoreGraphics
import CoreText
import Foundation
import PDFKit

enum PDFFixture {
    /// Writes a PDF whose pages carry the given lines, drawn top to bottom in 14 pt Helvetica.
    /// An empty line list makes a blank page.
    static func write(pages: [[String]], title: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fixture.pdf")
        var box = CGRect(x: 0, y: 0, width: 400, height: 600)
        var info: [CFString: Any] = [:]
        if let title { info[kCGPDFContextTitle] = title }
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let key = NSAttributedString.Key(kCTFontAttributeName as String)
        for lines in pages {
            ctx.beginPDFPage(nil)
            var y: CGFloat = 560
            for line in lines {
                let attributed = NSAttributedString(string: line, attributes: [key: font])
                ctx.textPosition = CGPoint(x: 40, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
                y -= 24
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// Attaches a top-level outline (title → 0-based page) to an open document, in memory.
    static func attachOutline(_ entries: [(String, Int)], to document: PDFDocument) {
        let root = PDFOutline()
        for (title, page) in entries {
            let entry = PDFOutline()
            entry.label = title
            if let p = document.page(at: page) {
                entry.destination = PDFDestination(page: p, at: CGPoint(x: 0, y: 600))
            }
            root.insertChild(entry, at: root.numberOfChildren)
        }
        document.outlineRoot = root
    }
}
