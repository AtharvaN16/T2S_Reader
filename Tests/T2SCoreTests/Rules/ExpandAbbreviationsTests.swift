import Testing
@testable import T2SCore

@Suite struct ExpandAbbreviationsTests {
    let rule = ExpandAbbreviationsRule()

    @Test(arguments: [
        ("Dr. Smith", "Doctor Smith"),
        ("Mr. and Mrs. Jones", "Mister and Missus Jones"),
        ("Ms. Lee", "Miz Lee"),
        ("Prof. Chen, Jr.", "Professor Chen, Junior"),
        ("cats vs. dogs", "cats versus dogs"),
        ("apples, pears, etc.", "apples, pears, et cetera"),
        ("see Fig. 3", "see Figure 3"),
        ("No. 5", "Number 5"),
        ("Say No. Then leave.", "Say No. Then leave."),
        ("e.g. this, i.e. that", "for example this, that is that"),
        ("approx. 40", "approximately 40"),
    ])
    func expands(input: String, expected: String) {
        let t = rule.apply(NormalizedText(source: input))
        #expect(t.spoken == expected)
        expectEveryWordMapsToSource(t)
    }

    /// Every row of the table has a test above or here: the alternation is built from the table,
    /// so a row a test never reaches could be mis-escaped without anyone noticing.
    @Test func everyRowExpands() {
        for (abbreviation, expansion) in ExpandAbbreviationsRule.table {
            let t = rule.apply(NormalizedText(source: "see \(abbreviation) 12"))
            #expect(t.spoken == "see \(expansion) 12", "\(abbreviation)")
        }
    }

    @Test func textWithoutADotIsUntouched() {
        let input = NormalizedText(source: "Dr Smith and Mrs Jones")
        #expect(rule.apply(input) == input)
    }

    @Test func expansionMapsToAbbreviation() {
        let t = rule.apply(NormalizedText(source: "Dr. Smith"))
        #expect(t.sourceRange(forSpoken: 0..<6) == 0..<3)
    }
}
