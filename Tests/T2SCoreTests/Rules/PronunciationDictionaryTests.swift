import Testing
@testable import T2SCore

@Suite struct PronunciationDictionaryTests {
    @Test func replacesWholeWordsOnly() {
        let rule = PronunciationDictionaryRule(entries: [
            PronunciationEntry(term: "Nguyen", replacement: "Nwin"),
        ])
        let t = rule.apply(NormalizedText(source: "Dr Nguyen and Nguyenson"))
        #expect(t.spoken == "Dr Nwin and Nguyenson")
        #expect(t.sourceRange(forSpoken: 3..<7) == 3..<9)
        expectEveryWordMapsToSource(t)
    }

    @Test func caseInsensitiveByDefault() {
        let rule = PronunciationDictionaryRule(entries: [PronunciationEntry(term: "SQL", replacement: "sequel")])
        #expect(rule.apply(NormalizedText(source: "sql and SQL")).spoken == "sequel and sequel")
    }

    @Test func caseSensitiveWhenAsked() {
        let rule = PronunciationDictionaryRule(entries: [PronunciationEntry(term: "US", replacement: "U S", caseSensitive: true)])
        #expect(rule.apply(NormalizedText(source: "the US and us")).spoken == "the U S and us")
    }

    @Test func termsEndingInSymbolsStillMatchWholeWords() {
        let rule = PronunciationDictionaryRule(entries: [PronunciationEntry(term: "C++", replacement: "see plus plus")])
        let t = rule.apply(NormalizedText(source: "I write C++ daily, not C+ or C++11."))
        #expect(t.spoken == "I write see plus plus daily, not C+ or C++11.")
        expectEveryWordMapsToSource(t)
    }
}
