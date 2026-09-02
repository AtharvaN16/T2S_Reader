import Foundation
import PDFKit
import T2SCore

/// Text PDFs through PDFKit (spec §2.1 rev 6): one `SourceBlock` per page after the running
/// header/footer filter (spec §4.1 rule 2); chapters from the outline when it has at least two
/// entries, else one chapter. Display stays in Readium's PDF navigator (Plan 4), which addresses
/// pages by `Position.progression`.
public struct PDFDocumentReader: DocumentReader {
    /// A PDF is one resource; the page travels in `progression` (Global Constraints).
    public static let resourceHref = "source.pdf"

    public let supportedTypes: Set<SourceType> = [.pdf]

    public init() {}

    public func read(fileURL: URL, sourceType: SourceType) async throws -> ReadDocument {
        guard let document = PDFDocument(url: fileURL) else {
            throw ImportError.unreadable("PDFKit could not open \(fileURL.lastPathComponent)")
        }
        if document.isLocked { throw ImportError.drmProtected }
        return try Self.read(document, fallbackTitle: fileURL.deletingPathExtension().lastPathComponent)
    }

    /// Entry point for an already-open document (tests attach an outline in memory).
    static func read(_ document: PDFDocument, fallbackTitle: String) throws -> ReadDocument {
        let pageCount = document.pageCount
        guard pageCount > 0 else { throw ImportError.noText }

        let rawLines: [[String]] = (0..<pageCount).map { i in
            (document.page(at: i)?.string ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let pages = RepeatedLineFilter.filter(pages: rawLines).map { $0.joined(separator: "\n") }
        guard pages.contains(where: { !$0.isEmpty }) else { throw ImportError.noText }

        var starts: [Int] = []
        var offset = 0
        for text in pages {
            starts.append(offset)
            offset += text.utf16.count + 1
        }
        func position(_ page: Int) -> Position {
            Position(resourceHref: resourceHref, progression: Double(page) / Double(pageCount), charOffset: starts[page])
        }
        func blocks(_ range: Range<Int>) -> [SourceBlock] {
            range.compactMap { page in
                pages[page].isEmpty ? nil : SourceBlock(text: pages[page], position: position(page))
            }
        }

        let attributes = document.documentAttributes ?? [:]
        let title = nonEmpty(attributes[PDFDocumentAttribute.titleAttribute] as? String) ?? fallbackTitle
        let author = nonEmpty(attributes[PDFDocumentAttribute.authorAttribute] as? String)

        var chapters: [ChapterInput] = []
        let entries = outlineEntries(document)
        if entries.count >= 2 {
            if entries[0].page > 0 {
                let front = blocks(0..<entries[0].page)
                if !front.isEmpty {
                    chapters.append(ChapterInput(title: "Front matter", position: front[0].position, blocks: front))
                }
            }
            for (i, entry) in entries.enumerated() {
                let end = i + 1 < entries.count ? entries[i + 1].page : pageCount
                let b = blocks(entry.page..<end)
                if !b.isEmpty { chapters.append(ChapterInput(title: entry.title, position: b[0].position, blocks: b)) }
            }
        } else {
            let b = blocks(0..<pageCount)
            chapters.append(ChapterInput(title: title, position: b[0].position, blocks: b))
        }

        let skipped = (0..<pageCount).filter { pages[$0].isEmpty }.map { "page \($0 + 1)" }
        let cover = document.page(at: 0).flatMap { PDFCover.jpeg(of: $0) }
        return ReadDocument(title: title, author: author, coverImage: cover, chapters: chapters, skippedResources: skipped)
    }

    /// Top-level outline entries that resolve to a page: sorted by page, one per page, blank
    /// labels replaced by "Section n".
    static func outlineEntries(_ document: PDFDocument) -> [(title: String, page: Int)] {
        guard let root = document.outlineRoot else { return [] }
        var found: [(title: String, page: Int, order: Int)] = []
        for i in 0..<root.numberOfChildren {
            guard let child = root.child(at: i), let page = child.destination?.page else { continue }
            let index = document.index(for: page)
            guard index >= 0, index < document.pageCount else { continue }
            found.append((child.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", index, i))
        }
        // Sort by page with outline order as the tie-break (Swift's sort is not stable), then keep
        // the first entry per page.
        found.sort { ($0.page, $0.order) < ($1.page, $1.order) }
        var seen = Set<Int>()
        var unique: [(title: String, page: Int)] = []
        for entry in found where seen.insert(entry.page).inserted {
            unique.append((entry.title.isEmpty ? "Section \(unique.count + 1)" : entry.title, entry.page))
        }
        return unique
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
