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

    @Test(arguments: [
        ("of the elite quarter of Daryaganj.14 The presence of sepoys.", "of the elite quarter of Daryaganj. The presence of sepoys."),
        ("the Gujars pounced on me'.18", "the Gujars pounced on me'."),
        ("gone out of business’.15 The rich moneylenders bore it.", "gone out of business’. The rich moneylenders bore it."),
        ("as he put it.”12 Nobody argued.", "as he put it.” Nobody argued."),
        ("Was it so?7 ‘Yes,’ she said.", "Was it so? ‘Yes,’ she said."),
    ])
    func dropsFootnoteNumbersGluedToSentenceEnds(input: String, expected: String) {
        let t = rule.apply(NormalizedText(source: input))
        #expect(t.spoken == expected)
        expectEveryWordMapsToSource(t)
    }

    @Test(arguments: [
        "It cost 3.14 dollars. Then more.",                 // a decimal: a digit before the point
        "Try v2.0 The sequel.",                              // a version, the same
        "See p.14 for the map.",                             // a page reference: lowercase after
        "Fig.3 shows the plan.",
        "It ended. 1857 was the year.",                      // a space before the number: a sentence of its own
        "Room 101 was locked.",
    ])
    func keepsDecimalsVersionsAndReferences(input: String) {
        #expect(rule.apply(NormalizedText(source: input)).spoken == input)
    }
}
