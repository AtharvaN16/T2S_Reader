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

    /// A heading broken by a `<br/>` reaches the builder as two blocks of one element — Readium's
    /// content iterator ends a text element at every `<br/>`. Left apart, the number is a synthesis
    /// call of one word, which Kokoro reads far above the voice's narration pitch (up to an octave
    /// on some voices; `spikes/findings/2026-09-16-lone-chapter-numbers.md`).
    @Test func joinsBlocksSplitOutOfOneElement() {
        let heading = ChapterInput(title: "3 An Uneasy Equilibrium", position: Position(resourceHref: "ch03.html", progression: 0), blocks: [
            SourceBlock(text: "3", position: Position(resourceHref: "ch03.html", progression: 0, charOffset: 0, cssSelector: "html > body > h2.h2")),
            SourceBlock(text: "AN UNEASY EQUILIBRIUM", position: Position(resourceHref: "ch03.html", progression: 0.01, charOffset: 2, cssSelector: "html > body > h2.h2")),
            SourceBlock(text: "By 1852, the two peoples were growing apart.", position: Position(resourceHref: "ch03.html", progression: 0.1, charOffset: 24, cssSelector: "html > body > p.noindent:nth-child(3)")),
        ])
        let t = TimelineBuilder.build(chapters: [heading], segmenter: Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength))
        #expect(t.utteranceCount == 2)
        #expect(t[utterance: 0].source == "3\nAN UNEASY EQUILIBRIUM")
        #expect(t[utterance: 0].spoken == "three AN uneasy equilibrium")
        // The join takes the first block's place, so nothing downstream moves.
        #expect(t[utterance: 0].position.charOffset == 0)
        #expect(t[utterance: 0].position.cssSelector == "html > body > h2.h2")
        #expect(t[utterance: 1].position.charOffset == 24)
    }

    /// Only blocks of the same element join. Two paragraphs are two blocks however short the first
    /// one is — a one-word line of dialogue keeps its own pause and its own highlight.
    @Test func leavesSeparateElementsApart() {
        let chapter = ChapterInput(title: "Talk", position: Position(resourceHref: "c.html", progression: 0), blocks: [
            SourceBlock(text: "Yes.", position: Position(resourceHref: "c.html", progression: 0, charOffset: 0, cssSelector: "p:nth-child(1)")),
            SourceBlock(text: "He said nothing more that evening.", position: Position(resourceHref: "c.html", progression: 0.5, charOffset: 5, cssSelector: "p:nth-child(2)")),
        ])
        let t = TimelineBuilder.build(chapters: [chapter], segmenter: Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength))
        #expect(t.utteranceCount == 2)
        #expect(t[utterance: 0].source == "Yes.")
    }

    /// Blocks of one element that are not adjacent in the extracted text cannot be joined by a
    /// newline without inventing text, so they are left alone.
    @Test func leavesNonAdjacentBlocksApart() {
        let chapter = ChapterInput(title: "Gap", position: Position(resourceHref: "c.html", progression: 0), blocks: [
            SourceBlock(text: "3", position: Position(resourceHref: "c.html", progression: 0, charOffset: 0, cssSelector: "h2")),
            SourceBlock(text: "A TITLE", position: Position(resourceHref: "c.html", progression: 0.01, charOffset: 40, cssSelector: "h2")),
        ])
        let t = TimelineBuilder.build(chapters: [chapter], segmenter: Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength))
        #expect(t.utteranceCount == 2)
    }

    /// A block with no selector at all — a PDF page — never joins to its neighbour.
    @Test func leavesBlocksWithoutASelectorApart() {
        let chapter = ChapterInput(title: "PDF", position: Position(resourceHref: "p.pdf", progression: 0), blocks: [
            SourceBlock(text: "3", position: Position(resourceHref: "p.pdf", progression: 0, charOffset: 0)),
            SourceBlock(text: "A TITLE", position: Position(resourceHref: "p.pdf", progression: 0.5, charOffset: 2)),
        ])
        let t = TimelineBuilder.build(chapters: [chapter], segmenter: Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength))
        #expect(t.utteranceCount == 2)
    }

    @Test func keepsEmptyChapters() {
        let t = TimelineBuilder.build(chapters: [ChapterInput(title: "Blank", position: Position(resourceHref: "x", progression: 0), blocks: [])],
                                      segmenter: Segmenter(normalizer: TextNormalizer()))
        #expect(t.chapters.count == 1)
        #expect(t.utteranceCount == 0)
    }
}
