import Foundation
import T2SCore
import T2SLibrary

/// Canned chapters for EPUB imports (Readium is iOS-only). Two chapters, three sentences, ~3.3 s estimated.
struct FakeReader: DocumentReader {
    let supportedTypes: Set<SourceType> = [.epub, .article]
    var title = "Fake Book"
    var chapterCount = 2

    func read(fileURL: URL, sourceType: SourceType) async throws -> ReadDocument {
        let chapters = (1...chapterCount).map { n in
            let href = "OEBPS/ch\(n).xhtml"
            let text = n == 1 ? "First sentence. Second sentence." : "Sentence number \(n) here."
            return ChapterInput(title: "Chapter \(n)", position: Position(resourceHref: href, progression: 0, charOffset: 0),
                                blocks: [SourceBlock(text: text, position: Position(resourceHref: href, progression: 0, charOffset: 0))])
        }
        return ReadDocument(title: title, author: "Fake Author", coverImage: nil, chapters: chapters)
    }
}
