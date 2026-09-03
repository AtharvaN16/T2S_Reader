import Foundation
import Testing
import T2SCore
@testable import T2SApp

@Suite struct ScrubberModelTests {
    func timeline(rendered: Int) -> Timeline {
        var utterances: [Utterance] = []
        for i in 0..<4 {
            let text = "Utterance \(i)."
            let n = text.utf16.count
            utterances.append(Utterance(position: Position(resourceHref: "a", progression: 0, charOffset: i * 20), source: text, spoken: text,
                                        spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], audioRef: i < rendered ? "k\(i)" : nil,
                                        duration: i < rendered ? .actual(10) : .estimated(10)))
        }
        return Timeline(chapters: [Chapter(title: "1", position: utterances[0].position, utterances: utterances)])
    }

    @Test func ticksFollowTheRenderFrontier() {
        let t = timeline(rendered: 2)                                        // 40 s, first 20 s rendered
        let m = ScrubberModel.make(timeline: t, timeIndex: TimeIndex(t), playhead: Playhead(utteranceIndex: 1, offset: 5), tickCount: 8)
        #expect(m.tickCount == 8)
        #expect(m.renderedTicks == [true, true, true, true, false, false, false, false])
        #expect(abs(m.fraction - 15.0 / 40.0) < 1e-9)
    }

    @Test func partiallyRenderedTickIsNotRendered() {
        let t = timeline(rendered: 1)                                        // 10 s of 40 rendered; 8 ticks of 5 s
        let m = ScrubberModel.make(timeline: t, timeIndex: TimeIndex(t), playhead: Playhead(utteranceIndex: 0), tickCount: 8)
        #expect(m.renderedTicks == [true, true, false, false, false, false, false, false])
        let m3 = ScrubberModel.make(timeline: t, timeIndex: TimeIndex(t), playhead: Playhead(utteranceIndex: 0), tickCount: 3)
        #expect(m3.renderedTicks == [false, false, false])                  // a 13.3 s tick spans an unrendered utterance
    }

    /// Two chapters, so the one-pass computation has to carry its running start time across a
    /// chapter boundary rather than restarting it.
    @Test func renderedTicksMarkAnyTickAnUnrenderedUtteranceOverlaps() {
        func utterance(_ i: Int, rendered: Bool) -> Utterance {
            let text = "Utterance \(i)."
            let n = text.utf16.count
            return Utterance(position: Position(resourceHref: "a", progression: 0, charOffset: i * 20), source: text, spoken: text,
                             spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], audioRef: rendered ? "k\(i)" : nil,
                             duration: rendered ? .actual(10) : .estimated(10))
        }
        // 40 s over two chapters of two utterances; utterance 2 (20…30 s) has no audio.
        let first = [utterance(0, rendered: true), utterance(1, rendered: true)]
        let second = [utterance(2, rendered: false), utterance(3, rendered: true)]
        let t = Timeline(chapters: [Chapter(title: "1", position: first[0].position, utterances: first),
                                    Chapter(title: "2", position: second[0].position, utterances: second)])
        let ticks = ScrubberModel.renderedTicks(timeline: t, timeIndex: TimeIndex(t), tickCount: 8)
        #expect(ticks == [true, true, true, true, false, false, true, true])
    }

    @Test func emptyTimeline() {
        let t = Timeline(chapters: [])
        let m = ScrubberModel.make(timeline: t, timeIndex: TimeIndex(t), playhead: Playhead(utteranceIndex: 0), tickCount: 5)
        #expect(m.renderedTicks == Array(repeating: false, count: 5) && m.fraction == 0)
    }
}
