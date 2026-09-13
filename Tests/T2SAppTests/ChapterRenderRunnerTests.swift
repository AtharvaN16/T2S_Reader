import Foundation
import Testing
import T2SCore
@testable import T2SApp

@MainActor
@Suite struct ChapterRenderRunnerTests {
    /// `FakeReader`'s book: chapter 1 is two sentences, chapter 2 one.
    private func makeRunner(_ fixtures: AppFixtures, engine: FakeEngine) -> ChapterRenderRunner {
        ChapterRenderRunner(library: fixtures.library, store: fixtures.store, audioStore: fixtures.audio,
                            engine: engine, arbiter: RenderArbiter())
    }

    /// Two chapters queued at once are one queue, drained in order: the engine sees chapter 1's
    /// sentences finished before chapter 2's starts, and each job's progress reaches its own length.
    @Test func theQueueDrainsInOrderAndProgressReachesEachChaptersLength() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let engine = FakeEngine(secondsPerCharacter: 0.01)
        let runner = makeRunner(fixtures, engine: engine)

        await runner.enqueue(documentID: id, chapters: [0, 1])
        await runner.awaitDrain()

        #expect(runner.queue.map(\.state) == [.ready, .ready])
        #expect(runner.queue.map(\.rendered) == runner.queue.map(\.utteranceCount))
        #expect(runner.queue.map(\.fraction) == [1, 1])
        #expect(runner.lastCompletion == ChapterRenderRunner.Completion(ready: 2, failed: 0))
        #expect(!runner.isWorking)

        // Timeline order, which for one-job-at-a-time is also chapter order; the refs and actual
        // durations are on disk, so the next load plays this without asking the engine again.
        let timeline = try #require(try await fixtures.store.timeline(for: id)).timeline
        let inOrder = (0 ..< timeline.utteranceCount).map { timeline[utterance: $0].spoken }
        #expect(await engine.requests.map(\.spoken) == inOrder)
        #expect(timeline.isFullyRendered)
    }

    /// What `chapterAhead` (or an earlier request) already put in the store is skipped, so a second
    /// request for the same chapter is not a second render of it.
    @Test func aChapterAlreadyInTheStoreRendersNothingASecondTime() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let engine = FakeEngine(secondsPerCharacter: 0.01)
        let runner = makeRunner(fixtures, engine: engine)

        await runner.enqueue(documentID: id, chapters: [0])
        await runner.awaitDrain()
        let first = await engine.requests.count
        #expect(first == 2)

        await runner.enqueue(documentID: id, chapters: [0])
        await runner.awaitDrain()

        #expect(await engine.requests.count == first)
        #expect(runner.queue.count == 1)                              // the same chapter, not a second row
        #expect(runner.queue[0].state == .ready)
        #expect(runner.queue[0].rendered == runner.queue[0].utteranceCount)
    }

    /// Heat stops the queue where it stands: the utterance in the engine finishes and is kept, the
    /// job goes back to the head with that progress, and the runner resumes itself when it clears.
    @Test func heatHoldsTheJobAtTheHeadOfTheQueueAndClearingItResumes() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let engine = FakeEngine(secondsPerCharacter: 0.01)
        let runner = makeRunner(fixtures, engine: engine)

        await engine.hold()
        await runner.enqueue(documentID: id, chapters: [0])
        var spins = 0
        while await engine.parkedCount < 1, spins < 10_000 { await Task.yield(); spins += 1 }
        #expect(await engine.parkedCount == 1)                        // one utterance is in the engine

        runner.deviceStateChanged(DeviceState(charging: false, thermalSerious: true, lowPowerMode: false, storeFull: false))
        await runner.awaitSchedulerCancel()                           // nothing new can be taken now
        await engine.release()
        await runner.awaitDrain()

        #expect(runner.hold == .hot)
        #expect(runner.queue[0].state == .queued)
        #expect(runner.queue[0].rendered == 1)
        #expect(runner.queue[0].utteranceCount == 2)
        #expect(runner.isWorking)

        runner.deviceStateChanged(.unplugged)
        await runner.awaitDrain()

        #expect(runner.hold == nil)
        #expect(runner.queue[0].state == .ready)
        #expect(runner.queue[0].rendered == 2)
        // The sentence rendered before the hold was not rendered again: three requests would mean
        // the resumed job had lost its progress.
        #expect(await engine.requests.count == 2)
    }

    /// The override buys one drain, not a setting: after the queue empties the next request meets
    /// the same heat again.
    @Test func continueAnywayRendersThroughHeatAndThenLapses() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let engine = FakeEngine(secondsPerCharacter: 0.01)
        let runner = makeRunner(fixtures, engine: engine)

        runner.deviceStateChanged(DeviceState(charging: false, thermalSerious: true, lowPowerMode: false, storeFull: false))
        await runner.enqueue(documentID: id, chapters: [0])
        #expect(runner.hold == .hot)
        #expect(await engine.requests.isEmpty)

        runner.continueAnyway()
        await runner.awaitDrain()
        #expect(runner.hold == nil)
        #expect(runner.queue[0].state == .ready)
        #expect(await engine.requests.count == 2)

        await runner.enqueue(documentID: id, chapters: [1])
        #expect(runner.hold == .hot)
        #expect(runner.queue[1].state == .queued)
        #expect(await engine.requests.count == 2)
    }

    /// The notice is app-wide now, so it is dismissible — and a dismissal must not be permanent.
    /// It covers the hold it was shown for; the next reason to stop says so again.
    @Test func dismissingTheHoldNoticeLastsOnlyAsLongAsThatHold() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let engine = FakeEngine(secondsPerCharacter: 0.01)
        let runner = makeRunner(fixtures, engine: engine)
        let hot = DeviceState(charging: false, thermalSerious: true, lowPowerMode: false, storeFull: false)

        runner.deviceStateChanged(hot)
        await runner.enqueue(documentID: id, chapters: [0])
        #expect(runner.hold == .hot)
        #expect(!runner.holdNoticeDismissed)

        runner.dismissHoldNotice()
        #expect(runner.holdNoticeDismissed)
        // Another report of the same heat is not a new reason to stop: the notice stays away.
        runner.deviceStateChanged(hot)
        #expect(runner.hold == .hot)
        #expect(runner.holdNoticeDismissed)

        // The heat lifts, the queue drains, and a second batch meets it again — a new notice.
        runner.deviceStateChanged(.unplugged)
        await runner.awaitDrain()
        #expect(runner.hold == nil)
        #expect(!runner.holdNoticeDismissed)

        runner.dismissHoldNotice()
        runner.deviceStateChanged(hot)
        await runner.enqueue(documentID: id, chapters: [1])
        #expect(runner.hold == .hot)
        #expect(!runner.holdNoticeDismissed)
    }
}
