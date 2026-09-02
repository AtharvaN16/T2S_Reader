import Testing
@testable import T2SCore

@Suite struct CollapseURLsTests {
    let rule = CollapseURLsRule()

    @Test(arguments: [
        ("see https://www.nytimes.com/2024/05/01/tech.html today", "see nytimes.com today"),
        ("at http://example.org", "at example.org"),
        ("visit www.apple.com/iphone now", "visit apple.com now"),
        ("email me at a@b.com", "email me at a@b.com"),
    ])
    func collapses(input: String, expected: String) {
        let t = rule.apply(NormalizedText(source: input))
        #expect(t.spoken == expected)
        expectEveryWordMapsToSource(t)
    }

    @Test func hostMapsToWholeURL() {
        let t = rule.apply(NormalizedText(source: "see https://www.nytimes.com/x today"))
        #expect(t.sourceRange(forSpoken: 4..<15) == 4..<30)
    }
}
