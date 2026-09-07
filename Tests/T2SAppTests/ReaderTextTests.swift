import Foundation
import Testing
import T2SCore
@testable import T2SApp

@Suite struct ReaderTextTests {
    let id = UUID()

    func utterance(_ text: String, href: String = "OEBPS/ch1.xhtml", selector: String? = "#c1 > p:nth-child(2)",
                   offset: Int = 0, progression: Double = 0) -> Utterance {
        let n = text.utf16.count
        return Utterance(position: Position(resourceHref: href, progression: progression, charOffset: offset, cssSelector: selector),
                         source: text, spoken: text, spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)],
                         duration: .estimated(1))
    }

    func timeline(_ chapters: [(String, [Utterance])]) -> Timeline {
        Timeline(chapters: chapters.map { Chapter(title: $0.0, position: $0.1.first?.position ?? Position(resourceHref: "x", progression: 0), utterances: $0.1) })
    }

    // Two utterances of one block form one paragraph; a new selector starts another.
    @Test func consecutiveUtterancesOfABlockFormOneParagraph() {
        let t = timeline([("One", [
            utterance("First sentence.", selector: "#c1 > p:nth-child(2)"),
            utterance("Second sentence.", selector: "#c1 > p:nth-child(2)", offset: 16),
            utterance("Another block.", selector: "#c1 > p:nth-child(3)"),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: "Someone")
        let kinds = text.paragraphs.map(\.kind)
        #expect(kinds == [.documentTitle, .byline, .chapterTitle, .body, .body])
        let p = text.paragraphs[3]
        #expect(p.text == "First sentence. Second sentence.")
        #expect(p.spans == [ReaderText.Span(utteranceIndex: 0, range: 0..<15), ReaderText.Span(utteranceIndex: 1, range: 16..<32)])
        #expect(p.chapterIndex == 0 && p.tintsWholeParagraph)
        #expect(text.paragraphs[4].text == "Another block.")
    }

    @Test func locationsAndLengthFollowTheFlattenedString() {
        let t = timeline([("One", [utterance("Hello there.")])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: nil)
        // "Book\nOne\nHello there." — no byline without an author.
        #expect(text.paragraphs.map(\.kind) == [.documentTitle, .chapterTitle, .body])
        #expect(text.paragraphs.map(\.location) == [0, 5, 9])
        #expect(text.length == 21)
        #expect(text.paragraphs[2].range == 9..<21)
    }

    @Test func aFirstBlockThatSaysTheChapterTitleIsTheChapterTitle() {
        let t = timeline([("The Storm", [
            utterance("THE STORM.", selector: "#h"),
            utterance("It began at dusk.", selector: "#c1 > p:nth-child(2)"),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: nil)
        #expect(text.paragraphs.map(\.kind) == [.documentTitle, .chapterTitle, .body])
        #expect(text.paragraphs[1].text == "THE STORM." && text.paragraphs[1].spans.count == 1)
    }

    @Test func aChapterTitleEqualToTheDocumentTitleIsNotDrawn() {
        let t = timeline([("Book", [utterance("Only paragraph.")])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: nil)
        #expect(text.paragraphs.map(\.kind) == [.documentTitle, .body])
    }

    @Test func aFirstSpokenBlockThatSaysTheDocumentTitleBecomesTheTitle() {
        let t = timeline([("Intro", [
            utterance("War and Peace", selector: "#t"),
            utterance("Well, Prince.", selector: "#c1 > p:nth-child(2)"),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "War and Peace", author: "Tolstoy")
        #expect(text.paragraphs.map(\.kind) == [.documentTitle, .byline, .chapterTitle, .body])
        #expect(text.paragraphs[0].spans.count == 1)          // the spoken title
        #expect(text.paragraphs[2].text == "Intro" && text.paragraphs[2].spans.isEmpty)
    }

    @Test func headingsComeFromTheSelectorTag() {
        #expect(ReaderText.kind(forSelector: "#c1 > h2:nth-child(1)") == .heading(level: 2))
        #expect(ReaderText.kind(forSelector: "html > body > section > h1.title") == .heading(level: 1))
        #expect(ReaderText.kind(forSelector: "#c1 > p:nth-child(2)") == .body)
        #expect(ReaderText.kind(forSelector: "#heading-id") == .body)
        #expect(ReaderText.kind(forSelector: "#c1 > h7") == .body)
        #expect(ReaderText.kind(forSelector: nil) == .body)
    }

    @Test func aPDFPageIsOneParagraphTintedPerUtterance() {
        let href = "source.pdf"
        let t = timeline([("Doc", [
            utterance("Line one\nline two.", href: href, selector: nil, offset: 0, progression: 0),
            utterance("Still page one.", href: href, selector: nil, offset: 19, progression: 0),
            utterance("Page two.", href: href, selector: nil, offset: 35, progression: 0.5),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "Doc", author: nil)
        #expect(text.paragraphs.map(\.kind) == [.documentTitle, .body, .body])
        let page = text.paragraphs[1]
        #expect(page.text == "Line one line two. Still page one.")   // the newline shows as a space
        #expect(!page.tintsWholeParagraph)
        #expect(text.tintRange(forUtterance: 1) == (page.location + 19)..<(page.location + 34))
        #expect(text.tintRange(forUtterance: 0) == page.location..<(page.location + 18))
    }

    @Test func displayTextKeepsLengths() {
        #expect(ReaderText.displayText("a\r\nb\tc\u{00A0}d") == "a  b c d")
        #expect(ReaderText.displayText("a\r\nb").utf16.count == "a\r\nb".utf16.count)
    }

    @Test func normalizedIgnoresCaseWhitespaceAndTrailingPunctuation() {
        #expect(ReaderText.normalized("  The   Storm. ") == "the storm")
        #expect(ReaderText.normalized("CHAPTER I:") == "chapter i")
    }

    @Test func wordAndTintRangesLandInTheParagraph() {
        let t = timeline([("One", [
            utterance("First sentence.", selector: "#p1"),
            utterance("Second sentence.", selector: "#p1", offset: 16),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: nil)
        let p = text.paragraphs[2]
        let h = HighlightRange(utteranceIndex: 1, position: t[utterance: 1].position, sourceRange: 7..<16)   // "sentence."
        #expect(text.wordRange(for: h) == (p.location + 16 + 7)..<(p.location + 16 + 16))
        #expect(text.tintRange(forUtterance: 1) == p.range)
        #expect(text.paragraphIndex(forUtterance: 1) == 2)
        #expect(text.paragraphIndex(forUtterance: 2) == nil)
        let outOfRange = HighlightRange(utteranceIndex: 1, position: t[utterance: 1].position, sourceRange: 10..<40)
        #expect(text.wordRange(for: outOfRange) == nil)
    }

    @Test func hitsMapOffsetsBackToUtterances() {
        let t = timeline([("One", [
            utterance("First sentence.", selector: "#p1"),
            utterance("Second sentence.", selector: "#p1", offset: 16),
        ])])
        let text = ReaderText(documentID: id, timeline: t, title: "Book", author: nil)
        let p = text.paragraphs[2]
        func hit(_ offset: Int) -> [Int] { text.hit(at: offset).map { [$0.utteranceIndex, $0.sourceOffset] } ?? [] }
        #expect(hit(p.location + 3) == [0, 3])
        #expect(hit(p.location + 16 + 7) == [1, 7])
        #expect(hit(p.location + 15) == [1, 0])            // the gap between spans → the next utterance
        #expect(hit(p.location + 32) == [1, 15])           // the paragraph's end → its last character
        #expect(text.hit(at: 1) == nil)                                // inside the drawn title
        #expect(text.hit(at: text.length + 5) == nil)
        #expect(text.paragraph(at: p.location + 4)?.id == 2)
        #expect(text.paragraph(at: 0)?.kind == .documentTitle)
    }

    @Test func anEmptyTimelineStillHasTheTitle() {
        let text = ReaderText(documentID: id, timeline: Timeline(chapters: []), title: "Book", author: nil)
        #expect(text.paragraphs.map(\.kind) == [.documentTitle])
        #expect(text.length == 4)
    }
}
