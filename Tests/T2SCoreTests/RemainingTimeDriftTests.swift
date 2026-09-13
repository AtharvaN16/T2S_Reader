import Foundation
import Testing
@testable import T2SCore

/// The Reader page prints its countdown as `total - elapsed`, and both halves come out of the
/// `TimeIndex` built from the timeline's utterance durations. Those durations start `.estimated`
/// (`DurationEstimator`, 15 UTF-16 units per second) and are overwritten with `.actual` as render
/// passes complete — passes that are not gated on playback state. These tests pin the consequence:
/// with the playhead frozen, the countdown still moves.
@Suite struct RemainingTimeDriftTests {
    /// Ten utterances, each estimated at 10 s; the playhead sits still inside the second one.
    private func timeline(actualAhead: Int, actualSeconds: TimeInterval) -> Timeline {
        let us = (0..<10).map { i -> Utterance in
            var u = makeUtterance("Utterance \(i).", seconds: 10, charOffset: i * 20)
            // Utterances 2… are the ones a render-ahead pass reaches while the reader is paused
            // at utterance 1; 0 and 1 keep their estimates so `elapsed` cannot move.
            if i >= 2 && i < 2 + actualAhead {
                u.audioRef = "k\(i)"
                u.duration = .actual(actualSeconds)
            }
            return u
        }
        return makeTimeline([us])
    }

    private let playhead = Playhead(utteranceIndex: 1, offset: 4)

    @Test func elapsedDoesNotMoveWhenUtterancesAheadAreRendered() {
        let before = TimeIndex(timeline(actualAhead: 0, actualSeconds: 8))
        let after = TimeIndex(timeline(actualAhead: 3, actualSeconds: 8))
        #expect(before.time(at: playhead) == 14)
        #expect(after.time(at: playhead) == 14)
    }

    @Test func remainingShrinksWhileTheReaderIsPaused() {
        let before = TimeIndex(timeline(actualAhead: 0, actualSeconds: 8))
        let after = TimeIndex(timeline(actualAhead: 3, actualSeconds: 8))
        let remainingBefore = before.totalDuration - before.time(at: playhead)
        let remainingAfter = after.totalDuration - after.time(at: playhead)
        #expect(remainingBefore == 86)                                       // 100 s total − 14 s in
        #expect(remainingAfter == 80)                                        // three 10 s estimates became 8 s
        #expect(remainingAfter < remainingBefore)
    }

    /// The drift has no preferred direction: an estimate that ran short makes the countdown grow.
    @Test func remainingGrowsWhenTheEstimateRanShort() {
        let before = TimeIndex(timeline(actualAhead: 0, actualSeconds: 13))
        let after = TimeIndex(timeline(actualAhead: 3, actualSeconds: 13))
        #expect(after.totalDuration - after.time(at: playhead)
                > before.totalDuration - before.time(at: playhead))
    }

    /// The estimator's own bias, stated once so the size of the drift is on the record: it assumes
    /// 15 UTF-16 units a second with a 0.5 s floor, and counts characters rather than speech. A
    /// chapter heading is the clearest case — "Chapter 2" is budgeted 0.6 s, which no voice says it
    /// in, so every heading in the book pushes the countdown the other way as it renders.
    @Test func theEstimatorCountsCharactersNotSpeech() {
        #expect(DurationEstimator.estimate(spoken: "Chapter 2") == 0.6)
        #expect(DurationEstimator.estimate(spoken: "No.") == DurationEstimator.floorSeconds)
        #expect(DurationEstimator.estimate(spoken: String(repeating: "a", count: 150)) == 10)
    }
}
