import Testing
@testable import T2SCore

@Suite struct HyphenationAndWhitespaceTests {
    @Test func rejoinsWordsHyphenatedAcrossLineBreaks() {
        let t = RejoinHyphenationRule().apply(NormalizedText(source: "the con-\ntinent was"))
        #expect(t.spoken == "the continent was")
        #expect(t.sourceRange(forSpoken: 4..<13) == 4..<15)   // "continent" ← "con-\ntinent"
        expectEveryWordMapsToSource(t)
    }

    @Test func keepsRealHyphens() {
        let t = RejoinHyphenationRule().apply(NormalizedText(source: "well-known"))
        #expect(t.spoken == "well-known")
    }

    @Test func rejoinsAcrossCRLF() {
        let t = RejoinHyphenationRule().apply(NormalizedText(source: "con-\r\ntinent"))
        #expect(t.spoken == "continent")
        expectEveryWordMapsToSource(t)
    }

    @Test func collapsesRunsAndTrims() {
        let t = CollapseWhitespaceRule().apply(NormalizedText(source: "  a  b\n\tc "))
        #expect(t.spoken == "a b c")
        #expect(t.sourceRange(forSpoken: 4..<5) == 8..<9)
        expectEveryWordMapsToSource(t)
    }

    @Test func singleSpacesAreUntouched() {
        let t = CollapseWhitespaceRule().apply(NormalizedText(source: "a b"))
        #expect(t.spans == [SpanMap(sourceRange: 0..<3, spokenRange: 0..<3)])
    }
}
