import Testing
@testable import T2SCore

@Suite struct SpellOutOnlyShortCapsTests {
    private func spoken(_ source: String) -> String {
        SpellOutOnlyShortCapsRule().apply(NormalizedText(source: source)).spoken
    }

    @Test(arguments: [
        ("SUPERFORECASTING", "superforecasting"),
        ("THE ART AND SCIENCE OF PREDICTION", "THE ART AND science OF prediction"),
        ("A READER'S GUIDE", "A reader's guide"),
    ])
    func aLongShoutBecomesAWord(source: String, expected: String) {
        #expect(spoken(source) == expected)
    }

    @Test(arguments: ["FBI", "USA", "PDF", "NASA", "I", "A"])
    func shortRunsAreLeftToBeSpelled(source: String) {
        #expect(spoken(source) == source)
    }

    /// Case only, so every offset still points where it did — the highlight and the bookmarks
    /// map through this text.
    @Test func theLengthAndTheMappingAreUnchanged() {
        let text = SpellOutOnlyShortCapsRule().apply(NormalizedText(source: "READ SUPERFORECASTING now"))
        #expect(text.spoken.utf16.count == "READ SUPERFORECASTING now".utf16.count)
        #expect(text.sourceRange(forSpoken: 5..<21) == 5..<21)
    }
}
