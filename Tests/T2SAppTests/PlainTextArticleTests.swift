import Testing
@testable import T2SApp

@Suite struct PlainTextArticleTests {
    @Test func paragraphsBecomeEscapedParagraphs() {
        let content = PlainTextArticle.content(title: "Notes", body: "Tom & Jerry <3\n\nSecond  paragraph.\nSame paragraph.\n\n\n")
        #expect(content.title == "Notes")
        #expect(content.bodyXHTML == "<p>Tom &amp; Jerry &lt;3</p><p>Second  paragraph.\nSame paragraph.</p>")
        #expect(content.sourceURL == nil && content.byline == nil)
    }

    /// XML 1.0 forbids the C0 controls; a form feed pasted out of a PDF would otherwise make the
    /// EPUB writer throw on text that looked ordinary.
    @Test func controlCharactersAreDropped() {
        let content = PlainTextArticle.content(title: "Notes", body: "Page one.\u{0C}Page two.\u{07}\u{7F}\tTabbed.")
        #expect(content.bodyXHTML == "<p>Page one.Page two.\tTabbed.</p>")
        #expect(!content.bodyXHTML.unicodeScalars.contains { $0.value == 0x0C })
    }

    @Test func defaultTitleIsTheFirstLineTrimmed() {
        #expect(PlainTextArticle.defaultTitle(for: "  A short note\nmore") == "A short note")
        #expect(PlainTextArticle.defaultTitle(for: String(repeating: "x", count: 120)) == String(repeating: "x", count: 80) + "…")
        #expect(PlainTextArticle.defaultTitle(for: " \n ") == "Pasted text")
        #expect(PlainTextArticle.content(title: "", body: "Hello there.").title == "Hello there.")
    }

    @Test func titleControlCharactersAreDropped() {
        let content = PlainTextArticle.content(title: "A\u{0C}B", body: "some text")
        #expect(content.title == "AB")
    }
}
