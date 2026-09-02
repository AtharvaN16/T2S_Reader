import Testing
@testable import T2SCore

@Suite struct HighlighterTests {
    func timed() -> Timeline {
        var u = Segmenter(normalizer: TextNormalizer()).segment(
            SourceBlock(text: "Dr. Smith paid $5.", position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 40))
        )[0]
        // spoken: "Doctor Smith paid five dollars."
        u.wordTimings = [
            WordTiming(spokenRange: 0..<6, start: 0.0, end: 0.5),
            WordTiming(spokenRange: 7..<12, start: 0.5, end: 1.0),
            WordTiming(spokenRange: 13..<17, start: 1.0, end: 1.4),
            WordTiming(spokenRange: 18..<22, start: 1.4, end: 1.8),
            WordTiming(spokenRange: 23..<31, start: 1.8, end: 2.4),
        ]
        u.duration = .actual(2.4)
        return makeTimeline([[u]])
    }

    @Test func projectsExpandedWordToAbbreviation() {
        let h = Highlighter.highlight(at: Playhead(utteranceIndex: 0, offset: 0.25), in: timed())
        #expect(h?.sourceRange == 0..<3)               // "Dr."
        #expect(h?.position.charOffset == 40)
    }

    @Test func projectsCurrencyWordsToWholeToken() {
        let t = timed()
        #expect(Highlighter.highlight(at: Playhead(utteranceIndex: 0, offset: 1.5), in: t)?.sourceRange == 15..<17)   // "five" → "$5"
        #expect(Highlighter.highlight(at: Playhead(utteranceIndex: 0, offset: 2.0), in: t)?.sourceRange == 15..<18)   // "dollars." → "$5."
    }

    @Test func fallsBackToProportionalWithoutTimings() {
        var t = timed()
        t[utterance: 0].wordTimings = nil
        t[utterance: 0].duration = .estimated(2.0)
        let h = Highlighter.highlight(at: Playhead(utteranceIndex: 0, offset: 0.6), in: t)   // 30% → "Smith"
        #expect(h?.sourceRange == 4..<9)
    }

    @Test func nilPastEnd() {
        #expect(Highlighter.highlight(at: Playhead(utteranceIndex: 5, offset: 0), in: timed()) == nil)
    }

    @Test func skipsInsertedWords() {
        var t = timed()
        var n = NormalizedText(source: "world")
        n.replace(spokenRange: 0..<0, with: "Hello ")
        t[utterance: 0] = Utterance(position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 0),
                                    source: n.source, spoken: n.spoken, spans: n.spans,
                                    duration: .actual(1),
                                    wordTimings: [WordTiming(spokenRange: 0..<5, start: 0, end: 0.5),
                                                  WordTiming(spokenRange: 6..<11, start: 0.5, end: 1)])
        #expect(Highlighter.highlight(at: Playhead(utteranceIndex: 0, offset: 0.1), in: t)?.sourceRange == 0..<5)
    }
}
