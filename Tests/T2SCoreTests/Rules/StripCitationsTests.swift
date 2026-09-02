import Testing
@testable import T2SCore

@Suite struct StripCitationsTests {
    let rule = StripCitationsRule()

    @Test func dropsBracketedNumbers() {
        let t = rule.apply(NormalizedText(source: "as shown [14] earlier [3, 7] and [2–5]."))
        #expect(t.spoken == "as shown earlier and.")
        #expect(t.sourceRange(forSpoken: 9..<16) == 14..<21)   // "earlier"
        expectEveryWordMapsToSource(t)
    }

    @Test func dropsSuperscriptMarkers() {
        let t = rule.apply(NormalizedText(source: "theory¹² holds"))
        #expect(t.spoken == "theory holds")
        expectEveryWordMapsToSource(t)
    }

    @Test func keepsNonNumericBrackets() {
        let t = rule.apply(NormalizedText(source: "he said [sic] that"))
        #expect(t.spoken == "he said [sic] that")
    }
}
