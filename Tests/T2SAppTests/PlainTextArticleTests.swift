import Testing
@testable import T2SApp

@Suite struct PlainTextArticleTests {
    @Test func paragraphsBecomeEscapedParagraphs() {
        let content = PlainTextArticle.content(title: "Notes", body: "Tom & Jerry <3\n\nSecond  paragraph.\nSame paragraph.\n\n\n")
        #expect(content.title == "Notes")
        #expect(content.bodyXHTML == "<p>Tom &amp; Jerry &lt;3</p><p>Second  paragraph.\nSame paragraph.</p>")
        #expect(content.sourceURL == nil && content.byline == nil)
    }

    @Test func defaultTitleIsTheFirstLineTrimmed() {
        #expect(PlainTextArticle.defaultTitle(for: "  A short note\nmore") == "A short note")
        #expect(PlainTextArticle.defaultTitle(for: String(repeating: "x", count: 120)) == String(repeating: "x", count: 80) + "…")
        #expect(PlainTextArticle.defaultTitle(for: " \n ") == "Pasted text")
        #expect(PlainTextArticle.content(title: "", body: "Hello there.").title == "Hello there.")
    }
}
