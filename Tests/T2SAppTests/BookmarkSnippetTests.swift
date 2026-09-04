import Testing
@testable import T2SApp

@Suite struct BookmarkSnippetTests {
    @Test func aShortSourceIsReturnedWhole() {
        #expect(BookmarkSnippet.make(from: "First sentence.", offset: 0) == "First sentence.")
    }
    @Test func startsAtTheOffset() {
        #expect(BookmarkSnippet.make(from: "First sentence. Second sentence.", offset: 16) == "Second sentence.")
    }
    @Test func cutsAtAWordBoundaryWithAnEllipsis() {
        let words = Array(repeating: "word", count: 40).joined(separator: " ")   // 199 units
        let snippet = BookmarkSnippet.make(from: words, offset: 0)
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.utf16.count <= BookmarkSnippet.maxLength)
        #expect(!snippet.dropLast().hasSuffix(" "))            // no trailing space before the ellipsis
        #expect(snippet.dropLast().split(separator: " ").allSatisfy { $0 == "word" })   // never a cut word
    }
    @Test func anOffsetPastTheEndIsEmpty() {
        #expect(BookmarkSnippet.make(from: "Short.", offset: 40) == "")
    }
    @Test func aNegativeOffsetClampsToTheStart() {
        #expect(BookmarkSnippet.make(from: "Short.", offset: -3) == "Short.")
    }
    @Test func aSpacelessRunOfSurrogatePairsIsCutOnACharacterBoundary() {
        let emoji = String(repeating: "😀", count: 60)   // 120 UTF-16 units, no spaces anywhere
        let snippet = BookmarkSnippet.make(from: emoji, offset: 0)
        #expect(!snippet.contains("\u{FFFD}"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.utf16.count <= 90)
    }
}
