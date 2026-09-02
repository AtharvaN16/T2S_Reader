import Foundation
import Testing
import T2SCore
import T2SLibrary
@testable import T2SReadium

@Suite struct ReadiumDocumentReaderTests {
    let reader = ReadiumDocumentReader()

    @Test func splitsChaptersByTableOfContents() async throws {
        let read = try await reader.read(fileURL: try EPUBFixture.twoChapterBook(), sourceType: .epub)
        #expect(read.title == "Fixture Book")
        #expect(read.author == "Ada Author")
        #expect(read.coverImage == nil)
        #expect(read.chapters.map(\.title) == ["Front matter", "Chapter One", "Chapter Two"])
        #expect(read.chapters.map { $0.blocks.map(\.text) } == [
            ["Title Page", "By Someone."],
            ["Chapter One", "First paragraph of one.", "Second paragraph of one."],
            ["Chapter Two", "Only paragraph of two."],
        ])
        #expect(read.skippedResources.count == 1)
        #expect(read.skippedResources[0].hasSuffix("blank.xhtml"))
    }

    @Test func positionsFollowTheEPUBRule() async throws {
        let read = try await reader.read(fileURL: try EPUBFixture.twoChapterBook(), sourceType: .epub)
        let one = read.chapters[1].blocks
        #expect(one.allSatisfy { $0.position.resourceHref.hasSuffix("ch1.xhtml") })
        #expect(one.map(\.position.charOffset) == [0, "Chapter One".utf16.count + 1,
                                                    "Chapter One".utf16.count + 1 + "First paragraph of one.".utf16.count + 1])
        let progressions = one.map(\.position.progression)
        #expect(progressions == progressions.sorted() && progressions[0] < progressions[2])
        #expect(one[1].position.cssSelector?.contains("p") == true)
        #expect(read.chapters[1].position == one[0].position)
        #expect(read.chapters[0].blocks[0].position.resourceHref != one[0].position.resourceHref)

        let timeline = TimelineBuilder.build(chapters: read.chapters, segmenter: Segmenter(normalizer: TextNormalizer()))
        #expect(timeline.utteranceCount == 7)
        for i in 0..<timeline.utteranceCount {
            #expect(PositionResolver.resolve(timeline[utterance: i].position, in: timeline) == Playhead(utteranceIndex: i))
        }
    }

    @Test func noTableOfContentsMeansOneChapterPerResource() async throws {
        let read = try await reader.read(fileURL: try EPUBFixture.noTOCBook(), sourceType: .epub)
        #expect(read.chapters.count == 2)
        #expect(read.chapters.map { $0.blocks.count } == [3, 2])
        #expect(read.chapters.map(\.title) == ["Section 1", "Section 2"])
    }

    @Test func readsAnArticleEPUBFromTheWriter() async throws {
        let article = ArticleContent(title: "Tom & Jerry", byline: "Jane Doe", sourceURL: URL(string: "https://example.com/t"),
                                     bodyXHTML: "<p>First paragraph.</p><p>Second one.</p>")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-article-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("source.epub")
        try ArticleEPUBWriter.write(article, to: url)
        let read = try await reader.read(fileURL: url, sourceType: .article)
        #expect(read.title == "Tom & Jerry")
        #expect(read.author == "Jane Doe")
        #expect(read.chapters.count == 1)
        #expect(read.chapters[0].blocks.map(\.text) == ["Tom & Jerry", "Jane Doe", "First paragraph.", "Second one."])
        #expect(read.skippedResources.isEmpty)
    }

    @Test func drmIsRejectedPlainly() async throws {
        await #expect(throws: ImportError.drmProtected) {
            _ = try await reader.read(fileURL: try EPUBFixture.drmBook(), sourceType: .epub)
        }
    }

    @Test func garbageIsRejected() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).epub")
        try Data("not an epub".utf8).write(to: url)
        await #expect(throws: ImportError.self) { _ = try await reader.read(fileURL: url, sourceType: .epub) }
    }
}
