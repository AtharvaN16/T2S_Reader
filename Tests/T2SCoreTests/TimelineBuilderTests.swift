import Testing
@testable import T2SCore

@Suite struct TimelineBuilderTests {
    let chapters = [
        ChapterInput(title: "One", position: Position(resourceHref: "c1.xhtml", progression: 0), blocks: [
            SourceBlock(text: "First para. Two sentences.", position: Position(resourceHref: "c1.xhtml", progression: 0, charOffset: 0)),
            SourceBlock(text: "Second para.", position: Position(resourceHref: "c1.xhtml", progression: 0.5, charOffset: 27)),
        ]),
        ChapterInput(title: "Two", position: Position(resourceHref: "c2.xhtml", progression: 0), blocks: [
            SourceBlock(text: "Only one.", position: Position(resourceHref: "c2.xhtml", progression: 0, charOffset: 0)),
        ]),
    ]

    @Test func buildsChaptersInOrder() {
        let t = TimelineBuilder.build(chapters: chapters, segmenter: Segmenter(normalizer: TextNormalizer()))
        #expect(t.chapters.map(\.title) == ["One", "Two"])
        #expect(t.utteranceRange(ofChapter: 0) == 0..<3)
        #expect(t.utteranceRange(ofChapter: 1) == 3..<4)
        #expect(t[utterance: 2].position.charOffset == 27)
        #expect(t.totalDuration > 0)
        #expect(t.isFullyRendered == false)
    }

    @Test func stampsVersions() {
        let t = TimelineBuilder.build(chapters: chapters, segmenter: Segmenter(normalizer: TextNormalizer()))
        #expect(t.schemaVersion == Versions.schema)
        #expect(t.segmenterVersion == Segmenter.version)
        #expect(t.normalizerVersion == TextNormalizer.version)
    }

    @Test func keepsEmptyChapters() {
        let t = TimelineBuilder.build(chapters: [ChapterInput(title: "Blank", position: Position(resourceHref: "x", progression: 0), blocks: [])],
                                      segmenter: Segmenter(normalizer: TextNormalizer()))
        #expect(t.chapters.count == 1)
        #expect(t.utteranceCount == 0)
    }
}
