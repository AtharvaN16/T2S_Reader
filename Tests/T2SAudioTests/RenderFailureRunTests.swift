import Foundation
import Testing
@testable import T2SAudio

/// One voice failure is a hiccup the reader never needs to hear about: the utterance is filled with
/// 200 ms of silence and the book carries on. Five in a row is the voice not working (owner,
/// 2026-09-13), and that is worth saying — once, plainly, with nothing to tap.
@Suite struct RenderFailureRunTests {
    @Test func oneFailureIsNotWorthSaying() {
        var run = RenderFailureRun()
        run.failed(utterance: 12)
        #expect(run.count == 1)
        #expect(!run.isPersistent)
    }

    /// The subtlety: a failed utterance is *followed* by a `.rendered` carrying its silence, for the
    /// same index (spec §6, `RenderScheduler`). Counting that as a recovery would reset the run on
    /// every failure and the fifth could never arrive.
    @Test func theSilenceThatFollowsAFailureIsNotARecovery() {
        var run = RenderFailureRun()
        for i in 0..<5 {
            run.failed(utterance: i)
            run.rendered(utterance: i)              // the 200 ms of silence for that same utterance
        }
        #expect(run.count == 5)
        #expect(run.isPersistent)
    }

    @Test func aGenuineRenderClearsTheRun() {
        var run = RenderFailureRun()
        run.failed(utterance: 1)
        run.failed(utterance: 2)
        run.rendered(utterance: 3)                  // a different utterance: the voice is working
        #expect(run.count == 0)
        #expect(!run.isPersistent)
    }

    @Test func fiveIsTheThreshold() {
        var run = RenderFailureRun()
        for i in 0..<4 { run.failed(utterance: i) }
        #expect(!run.isPersistent)
        run.failed(utterance: 4)
        #expect(run.isPersistent)
    }

    /// Having surfaced, it stops again the moment the voice comes back — the old `lastRenderError`
    /// was only ever cleared by loading another document, so one hiccup pinned a red line under the
    /// scrubber for the rest of the session.
    @Test func recoveryStopsItBeingPersistent() {
        var run = RenderFailureRun()
        for i in 0..<6 { run.failed(utterance: i); run.rendered(utterance: i) }
        #expect(run.isPersistent)
        run.rendered(utterance: 99)
        #expect(!run.isPersistent)
        #expect(run.count == 0)
    }

    @Test func resetClearsEverything() {
        var run = RenderFailureRun()
        for i in 0..<7 { run.failed(utterance: i) }
        run.reset()
        #expect(run.count == 0)
        #expect(!run.isPersistent)
    }
}
