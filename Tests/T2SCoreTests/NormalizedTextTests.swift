import Testing
@testable import T2SCore

@Suite struct NormalizedTextTests {
    @Test func identityMapsOneToOne() {
        let t = NormalizedText(source: "Dr. Smith")
        #expect(t.spoken == "Dr. Smith")
        #expect(t.spans == [SpanMap(sourceRange: 0..<9, spokenRange: 0..<9)])
        #expect(t.sourceRange(forSpoken: 4..<9) == 4..<9)
    }

    @Test func expansionMapsWholeSpanToWholeToken() {
        var t = NormalizedText(source: "Dr. Smith")
        t.replace(spokenRange: 0..<3, with: "Doctor")
        #expect(t.spoken == "Doctor Smith")
        #expect(t.sourceRange(forSpoken: 0..<6) == 0..<3)
        #expect(t.sourceRange(forSpoken: 2..<4) == 0..<3)      // partial of atomic → whole token
        #expect(t.sourceRange(forSpoken: 7..<12) == 4..<9)     // shifted linear tail
        #expect(t.spokenRange(forSource: 0..<3) == 0..<6)
        #expect(t.spokenRange(forSource: 4..<9) == 7..<12)
        expectEveryWordMapsToSource(t)
    }

    @Test func deletionLeavesEmptySpokenSpan() {
        var t = NormalizedText(source: "text [14] more")
        t.replace(spokenRange: 4..<9, with: "")
        #expect(t.spoken == "text more")
        #expect(t.sourceRange(forSpoken: 5..<9) == 10..<14)
        #expect(t.spans.contains(SpanMap(sourceRange: 4..<9, spokenRange: 4..<4)))
        #expect(t.spokenRange(forSource: 5..<9).isEmpty)       // "[14]" has no spoken text
        expectEveryWordMapsToSource(t)
    }

    @Test func insertionMapsToSourcePoint() {
        var t = NormalizedText(source: "world")
        t.replace(spokenRange: 0..<0, with: "Hello ")
        #expect(t.spoken == "Hello world")
        #expect(t.sourceRange(forSpoken: 0..<5) == 0..<0)
        #expect(t.sourceRange(forSpoken: 6..<11) == 0..<5)
    }

    @Test func replacementInsideLinearSpanSplitsIt() {
        var t = NormalizedText(source: "a 1 b")
        t.replace(spokenRange: 2..<3, with: "one")
        #expect(t.spoken == "a one b")
        #expect(t.spans == [
            SpanMap(sourceRange: 0..<2, spokenRange: 0..<2),
            SpanMap(sourceRange: 2..<3, spokenRange: 2..<5),
            SpanMap(sourceRange: 3..<5, spokenRange: 5..<7),
        ])
    }

    @Test func reverseOrderReplacementsKeepMapping() {
        var t = NormalizedText(source: "Mr. and Dr. X")
        t.replace(spokenRange: 8..<11, with: "Doctor")   // later match first
        t.replace(spokenRange: 0..<3, with: "Mister")
        #expect(t.spoken == "Mister and Doctor X")
        #expect(t.sourceRange(forSpoken: 0..<6) == 0..<3)
        #expect(t.sourceRange(forSpoken: 11..<17) == 8..<11)
        #expect(t.sourceRange(forSpoken: 18..<19) == 12..<13)
        expectEveryWordMapsToSource(t)
    }

    @Test func partialOverlapOfAtomicSpanKeepsWholeSource() {
        var t = NormalizedText(source: "Dr.")
        t.replace(spokenRange: 0..<3, with: "Doctor")
        t.replace(spokenRange: 3..<6, with: "TOR")          // touches half of the atomic span
        #expect(t.spoken == "DocTOR")
        #expect(t.sourceRange(forSpoken: 0..<3) == 0..<3)
        #expect(t.sourceRange(forSpoken: 3..<6) == 0..<3)
    }
}
