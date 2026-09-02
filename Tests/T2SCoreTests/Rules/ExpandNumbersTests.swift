import Testing
@testable import T2SCore

@Suite struct ExpandNumbersTests {
    let rule = ExpandNumbersRule()

    @Test(arguments: [
        ("I have 3 cats", "I have three cats"),
        ("about 1,200 people", "about one thousand two hundred people"),
        ("in 1999 and 2024", "in nineteen ninety-nine and twenty twenty-four"),
        ("the 21st century", "the twenty-first century"),
        ("costs $5", "costs five dollars"),
        ("costs $1", "costs one dollar"),
        ("costs $2.50", "costs two dollars and fifty cents"),
        ("costs $0.99", "costs ninety-nine cents"),
        ("costs £40 or €3", "costs forty pounds or three euros"),
        ("up 12% today", "up twelve percent today"),
        ("pi is 3.14", "pi is three point one four"),
        ("ran 5 km in 30 min", "ran five kilometers in thirty minutes"),
        ("1 km", "one kilometer"),
        ("2.5% of 40 kg", "two point five percent of forty kilograms"),
        ("version 2.0.1", "version 2.0.1"),
        ("born in 1999.", "born in nineteen ninety-nine."),
        ("count 3.", "count three."),
    ])
    func expands(input: String, expected: String) {
        let t = rule.apply(NormalizedText(source: input))
        #expect(t.spoken == expected)
        expectEveryWordMapsToSource(t)
    }

    @Test func currencyMapsToWholeToken() {
        let t = rule.apply(NormalizedText(source: "costs $2.50 now"))
        #expect(t.sourceRange(forSpoken: 6..<33) == 6..<11)   // "two dollars and fifty cents" ← "$2.50"
    }
}
