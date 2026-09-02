import Foundation
import T2SCore
@testable import T2SLibrary

/// Records every file a reader is asked to open.
actor ReadLog {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}

/// Stands in for `ReadiumDocumentReader` with canned chapters: two resources, three sentences.
struct FakeDocumentReader: DocumentReader {
    let supportedTypes: Set<SourceType> = [.epub, .article]
    var title = "Fake Book"
    var chapters: [ChapterInput] = [
        ChapterInput(title: "One", position: Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0, charOffset: 0), blocks: [
            SourceBlock(text: "First sentence. Second sentence.",
                        position: Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0, charOffset: 0)),
        ]),
        ChapterInput(title: "Two", position: Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0), blocks: [
            SourceBlock(text: "Third sentence.",
                        position: Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0)),
        ]),
    ]
    var skipped: [String] = []
    var failure: ImportError?
    let log = ReadLog()

    func read(fileURL: URL, sourceType: SourceType) async throws -> ReadDocument {
        await log.record(fileURL)
        if let failure { throw failure }
        return ReadDocument(title: title, author: "Fake Author", coverImage: Data([0xFF, 0xD8, 0xFF, 0xE0]),
                            chapters: chapters, skippedResources: skipped)
    }
}
