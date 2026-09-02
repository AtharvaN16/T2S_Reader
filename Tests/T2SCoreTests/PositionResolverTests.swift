// Tests/T2SCoreTests/PositionResolverTests.swift
import Testing
@testable import T2SCore

@Suite struct PositionResolverTests {
    // Chapter 1: "Alpha beta." (0..<11) "Gamma delta epsilon." (12..<32)   Chapter 2: "Zeta." (0..<5)
    let t = makeTimeline([
        [makeUtterance("Alpha beta.", seconds: 2, charOffset: 0, progression: 0.0),
         makeUtterance("Gamma delta epsilon.", seconds: 4, charOffset: 12, progression: 0.4)],
        [makeUtterance("Zeta.", seconds: 1, href: "ch2.xhtml", charOffset: 0, progression: 0.0)],
    ])

    @Test func exactCharOffsetInsideUtterance() {
        let ph = PositionResolver.resolve(Position(resourceHref: "ch1.xhtml", progression: 0.4, charOffset: 22), in: t)
        #expect(ph.utteranceIndex == 1)
        #expect(abs(ph.offset - 2.0) < 0.01)          // 10 of 20 chars → half of 4 s
    }

    @Test func charOffsetInGapSnapsToPrecedingUtterance() {
        let ph = PositionResolver.resolve(Position(resourceHref: "ch1.xhtml", progression: 0.3, charOffset: 11), in: t)
        #expect(ph == Playhead(utteranceIndex: 0, offset: 2.0))
    }

    @Test func progressionOnlyFallsBackToNearest() {
        let ph = PositionResolver.resolve(Position(resourceHref: "ch1.xhtml", progression: 0.9), in: t)
        #expect(ph == Playhead(utteranceIndex: 1, offset: 0))
    }

    @Test func unknownHrefFallsBackToChapterStartNeverDocumentStart() {
        let ph = PositionResolver.resolve(Position(resourceHref: "ch2.xhtml", progression: 0.5, charOffset: 9_999), in: t)
        #expect(ph.utteranceIndex == 2)
        let ph2 = PositionResolver.resolve(Position(resourceHref: "missing.xhtml", progression: 0.5), in: t)
        #expect(ph2 == Playhead(utteranceIndex: 0, offset: 0))
    }

    @Test func roundTripsThroughPosition() {
        let ph = Playhead(utteranceIndex: 1, offset: 1.0)
        let p = PositionResolver.position(for: ph, in: t)
        #expect(p.resourceHref == "ch1.xhtml")
        #expect(p.charOffset == 17)                     // 1 of 4 s → 5 of 20 chars
        #expect(PositionResolver.resolve(p, in: t) == ph)
    }

    @Test func usesWordTimingsWhenPresent() {
        var t = t
        t[utterance: 1].wordTimings = [
            WordTiming(spokenRange: 0..<5, start: 0, end: 1),      // Gamma
            WordTiming(spokenRange: 6..<11, start: 1, end: 3),     // delta
            WordTiming(spokenRange: 12..<20, start: 3, end: 4),    // epsilon.
        ]
        let ph = PositionResolver.resolve(Position(resourceHref: "ch1.xhtml", progression: 0.4, charOffset: 18), in: t)
        #expect(ph.utteranceIndex == 1)
        #expect(ph.offset == 1.0)                       // "delta" starts at source 18 → 1.0 s
        #expect(PositionResolver.position(for: Playhead(utteranceIndex: 1, offset: 3.5), in: t).charOffset == 24)
    }

    @Test func survivesResegmentation() {
        let text = "One sentence here. Another sentence follows, with a clause; and another clause here. Third."
        let block = SourceBlock(text: text, position: Position(resourceHref: "c.xhtml", progression: 0, charOffset: 0))
        let coarse = TimelineBuilder.build(chapters: [ChapterInput(title: "C", position: block.position, blocks: [block])],
                                           segmenter: Segmenter(normalizer: TextNormalizer(), maxUtteranceLength: 300))
        let fine = TimelineBuilder.build(chapters: [ChapterInput(title: "C", position: block.position, blocks: [block])],
                                         segmenter: Segmenter(normalizer: TextNormalizer(), maxUtteranceLength: 30))
        #expect(fine.utteranceCount > coarse.utteranceCount)
        for i in 0..<coarse.utteranceCount {
            let u = coarse[utterance: i]
            let ph = Playhead(utteranceIndex: i, offset: u.duration.seconds / 2)
            let p = PositionResolver.position(for: ph, in: coarse)
            let re = PositionResolver.resolve(p, in: fine)
            let landed = fine[utterance: re.utteranceIndex]
            let landedChar = landed.position.charOffset! + landed.sourceOffset(atTime: re.offset)
            #expect(abs(landedChar - p.charOffset!) <= 1, "utterance \(i)")
        }
    }
}
