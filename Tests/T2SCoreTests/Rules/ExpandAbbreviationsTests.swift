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

    @Test func expansionMapsToAbbreviation() {
        let t = rule.apply(NormalizedText(source: "Dr. Smith"))
        #expect(t.sourceRange(forSpoken: 0..<6) == 0..<3)
    }
}
