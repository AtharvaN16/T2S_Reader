import Testing
@testable import T2SCore

/// A hyphen joining two words is a word break for the engine, not a dash: MisakiSwift turns every
/// hyphen token into Kokoro's `—`, which the model reads as a clause pause ("cost — cutting").
/// Finding: `spikes/findings/2026-09-08-ticks-and-hyphens.md`.
@Suite struct SplitHyphenatedCompoundsTests {
    @Test(arguments: [
        ("the commander-in-chief spoke", "the commander in chief spoke"),
        ("a cost-cutting plan", "a cost cutting plan"),
        ("twenty-five re-entered", "twenty five re entered"),
        ("COVID-19 and the F-16", "COVID 19 and the F 16"),
        ("a well\u{2010}known non\u{2011}breaking case", "a well known non breaking case"),
    ])
    func splitsHyphensBetweenWords(input: String, expected: String) {
        let t = SplitHyphenatedCompoundsRule().apply(NormalizedText(source: input))
        #expect(t.spoken == expected)
        expectEveryWordMapsToSource(t)
    }

    @Test(arguments: [
        "well - maybe",                                  // a spaced dash is a real pause
        "wait -- no",
        "1990-1995",                                     // a range keeps its beat
        "call 555-1234",
        "an em\u{2014}dash and an en\u{2013}dash",
        "-5 degrees",
    ])
    func leavesDashesAndNumbersAlone(input: String) {
        #expect(SplitHyphenatedCompoundsRule().apply(NormalizedText(source: input)).spoken == input)
    }

    @Test func eachWordStillMapsToItsOwnSource() {
        let t = SplitHyphenatedCompoundsRule().apply(NormalizedText(source: "commander-in-chief"))
        #expect(t.sourceRange(forSpoken: 10..<12) == 10..<12)   // "in"
        #expect(t.sourceRange(forSpoken: 13..<18) == 13..<18)   // "chief"
    }
}
