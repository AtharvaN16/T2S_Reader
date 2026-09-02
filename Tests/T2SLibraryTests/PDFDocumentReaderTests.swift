import Foundation
import PDFKit
import Testing
import T2SCore
@testable import T2SLibrary

@Suite struct PDFDocumentReaderTests {
    let header = "The Example Book"
    func body(_ i: Int) -> String { "Body sentence number \(i) is here." }
    /// Running header on top, page number at the bottom, one body sentence between.
    func fourPages() -> [[String]] { (1...4).map { [header, body($0), "Page \($0)"] } }

    @Test func stripsRunningHeadersAndPageNumbers() async throws {
        let url = try PDFFixture.write(pages: fourPages(), title: "Example")
        let read = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        #expect(read.title == "Example")
        #expect(read.author == nil)
        #expect(read.chapters.count == 1)
        #expect(read.chapters[0].title == "Example")
        #expect(read.chapters[0].blocks.map(\.text) == (1...4).map(body))
        #expect(read.skippedResources.isEmpty)
    }

    @Test func positionsAreMonotonicAndResolve() async throws {
        let url = try PDFFixture.write(pages: fourPages())
        let read = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        #expect(read.title == "fixture")                                    // file name, no title attribute
        let blocks = read.chapters[0].blocks
        #expect(blocks.map(\.position.resourceHref) == Array(repeating: PDFDocumentReader.resourceHref, count: 4))
        #expect(blocks.map(\.position.progression) == [0, 0.25, 0.5, 0.75])
        var expected: [Int] = [], offset = 0
        for i in 1...4 { expected.append(offset); offset += body(i).utf16.count + 1 }
        #expect(blocks.map(\.position.charOffset) == expected)
        #expect(read.chapters[0].position == blocks[0].position)

        let timeline = TimelineBuilder.build(chapters: read.chapters, segmenter: Segmenter(normalizer: TextNormalizer()))
        #expect(timeline.utteranceCount == 4)
        for i in 0..<4 {
            #expect(PositionResolver.resolve(timeline[utterance: i].position, in: timeline) == Playhead(utteranceIndex: i))
        }
    }

    @Test func outlineBecomesChapters() throws {
        let url = try PDFFixture.write(pages: fourPages())
        let document = try #require(PDFDocument(url: url))
        PDFFixture.attachOutline([("Part Two", 3), ("Part One", 1), ("  ", 1)], to: document)
        let read = try PDFDocumentReader.read(document, fallbackTitle: "fixture")
        #expect(read.chapters.map(\.title) == ["Front matter", "Part One", "Part Two"])
        #expect(read.chapters.map { $0.blocks.count } == [1, 2, 1])
        #expect(read.chapters[1].position.progression == 0.25)
        #expect(read.chapters[1].position == read.chapters[1].blocks[0].position)
    }

    @Test func fewerThanTwoOutlineEntriesMeansOneChapter() throws {
        let url = try PDFFixture.write(pages: fourPages())
        let document = try #require(PDFDocument(url: url))
        PDFFixture.attachOutline([("Only", 0)], to: document)
        let read = try PDFDocumentReader.read(document, fallbackTitle: "fixture")
        #expect(read.chapters.map(\.title) == ["fixture"])
        #expect(read.chapters[0].blocks.count == 4)
    }

    @Test func blankPagesAreSkippedAndReported() async throws {
        let url = try PDFFixture.write(pages: [["Some text on page one."], [], ["More text on page three."]])
        let read = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        #expect(read.chapters.count == 1)
        #expect(read.chapters[0].blocks.map(\.text) == ["Some text on page one.", "More text on page three."])
        #expect(read.chapters[0].blocks.map(\.position.progression) == [0, 2.0 / 3.0])
        #expect(read.skippedResources == ["page 2"])
    }

    @Test func noTextIsRejected() async throws {
        let url = try PDFFixture.write(pages: [[], []])
        await #expect(throws: ImportError.noText) {
            _ = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        }
    }

    @Test func coverIsAJPEG() async throws {
        let url = try PDFFixture.write(pages: fourPages())
        let read = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        let cover = try #require(read.coverImage)
        #expect(cover.prefix(2) == Data([0xFF, 0xD8]))
        #expect(cover.count > 1_000)
    }

    @Test func unreadableFileIsRejected() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-pdf-\(UUID().uuidString).pdf")
        try Data("hello".utf8).write(to: url)
        await #expect(throws: ImportError.self) {
            _ = try await PDFDocumentReader().read(fileURL: url, sourceType: .pdf)
        }
    }
}
