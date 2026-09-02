import Testing
@testable import T2SCore

@Suite struct TimeIndexTests {
    let t = makeTimeline([
        [makeUtterance("a", seconds: 1), makeUtterance("b", seconds: 2)],
        [makeUtterance("c", seconds: 3, href: "ch2.xhtml"), makeUtterance("d", seconds: 4, href: "ch2.xhtml")],
    ])

    @Test func matchesTimelineStartTimes() {
        let ix = TimeIndex(t)
        #expect(ix.utteranceCount == 4)
        #expect(ix.totalDuration == 10)
        for i in 0...4 { #expect(ix.startTime(ofUtterance: i) == t.startTime(ofUtterance: i)) }
        #expect(ix.duration(ofUtterance: 2) == 3)
    }

    @Test func timeAndPlayheadRoundTrip() {
        let ix = TimeIndex(t)
        #expect(ix.time(at: Playhead(utteranceIndex: 2, offset: 1.5)) == 4.5)
        #expect(ix.playhead(atTime: 4.5) == Playhead(utteranceIndex: 2, offset: 1.5))
        #expect(ix.playhead(atTime: 3.0) == Playhead(utteranceIndex: 2, offset: 0))     // boundary belongs to the next utterance
        #expect(ix.playhead(atTime: -1) == Playhead(utteranceIndex: 0, offset: 0))
        #expect(ix.playhead(atTime: 10) == Playhead(utteranceIndex: 3, offset: 4))      // clamped to the end
        #expect(ix.playhead(atTime: 99) == Playhead(utteranceIndex: 3, offset: 4))
    }

    @Test func advanceCrossesBoundaries() {
        let ix = TimeIndex(t)
        #expect(ix.advance(Playhead(utteranceIndex: 0, offset: 0.5), by: 1.0) == Playhead(utteranceIndex: 1, offset: 0.5))
        #expect(ix.advance(Playhead(utteranceIndex: 1, offset: 1.0), by: -2.0) == Playhead(utteranceIndex: 0, offset: 0))
        #expect(ix.advance(Playhead(utteranceIndex: 3, offset: 1.0), by: 100) == Playhead(utteranceIndex: 3, offset: 4))
        #expect(ix.clamp(Playhead(utteranceIndex: 9, offset: 0)) == Playhead(utteranceIndex: 3, offset: 4))
        #expect(ix.clamp(Playhead(utteranceIndex: 1, offset: 7)) == Playhead(utteranceIndex: 1, offset: 2))
    }

    @Test func emptyTimeline() {
        let ix = TimeIndex(makeTimeline([[]]))
        #expect(ix.utteranceCount == 0)
        #expect(ix.totalDuration == 0)
        #expect(ix.playhead(atTime: 5) == Playhead(utteranceIndex: 0, offset: 0))
    }

    @Test func playheadIsComparable() {
        #expect(Playhead(utteranceIndex: 1, offset: 9) < Playhead(utteranceIndex: 2, offset: 0))
        #expect(Playhead(utteranceIndex: 2, offset: 0.5) < Playhead(utteranceIndex: 2, offset: 1))
    }

    /// Spec §8: replacing an estimate with an actual never moves the playhead.
    @Test func actualDurationsNeverMoveThePlayhead() {
        var t = t
        let ph = Playhead(utteranceIndex: 2, offset: 1.5)
        let before = TimeIndex(t).time(at: ph)
        t[utterance: 0].duration = .actual(1.7)
        t[utterance: 1].duration = .actual(2.9)
        let after = TimeIndex(t).time(at: ph)
        #expect(ph == Playhead(utteranceIndex: 2, offset: 1.5))          // the playhead itself is untouched
        #expect(before == 4.5 && abs(after - 6.1) < 1e-9)                 // only the derived display time moved
        #expect(Highlighter.highlight(at: ph, in: t)?.utteranceIndex == 2)
    }
}
