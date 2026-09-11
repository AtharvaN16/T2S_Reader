import Foundation
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// The two-phase load: ready with the smallest bucket, the rest behind it, every stage admitted
/// through the gate the app hands in.
@Suite(.serialized) struct KokoroCoreMLLoadTests {
    static func voiceID(_ voice: String) -> String {
        KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: voice).rawValue
    }

    /// Readiness needs the duration models and the smallest and largest buckets' three stages each:
    /// eight of fourteen, with every piece still fitting a bucket the engine holds.
    @Test func theReadySetIsEightStagesAndTheRestFollowSmallestFirst() {
        #expect(KokoroCoreMLResources.readyBuckets == [3, 15])
        #expect(KokoroCoreMLResources.laterBuckets == [7, 10])
        #expect(KokoroCoreMLResources.stageNames(buckets: KokoroCoreMLResources.readyBuckets) == [
            "kokoro_duration_t128", "kokoro_duration_t256", "kokoro_f0ntrain_t120", "kokoro_f0ntrain_t600",
            "kokoro_decoder_pre_3s", "kokoro_decoder_pre_15s", "kokoro_decoder_har_post_3s", "kokoro_decoder_har_post_15s",
        ])
        #expect(KokoroCoreMLResources.stageNames(buckets: [7], durationTokenLengths: []) == [
            "kokoro_f0ntrain_t280", "kokoro_decoder_pre_7s", "kokoro_decoder_har_post_7s",
        ])
    }

    /// `preload()` returns with the ready buckets alone and a long sentence renders whole in them,
    /// then every bucket lands and a fresh render uses them.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func rendersBeforeTheLaterBucketsLandAndHoldsEveryBucketAfter() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources())
        var progress: [Int] = []
        let seen = OSAllocatedUnfairLockBox<[Int]>([])
        await engine.setLoadProgress { loaded, total in seen.value.append(loaded * 100 + total) }
        try await engine.preload()
        let atReadiness = await engine.loadedBuckets
        #expect(atReadiness.first == 3 && atReadiness.last == 15)
        #expect(atReadiness.count <= 4)
        progress = seen.value
        #expect(progress.contains(8_14))                            // the eighth stage of fourteen, reported

        let early = try await engine.synthesize(.init(spoken: KokoroCoreMLEngineTests.longSentence, voiceID: Self.voiceID("af_heart")))
        #expect(early.audio.duration > 15)
        #expect(early.wordTimings.count == KokoroCoreMLEngineTests.longSentence.split(separator: " ").count)

        try await engine.awaitFullLoad()
        #expect(await engine.loadedBuckets == [3, 7, 10, 15])
        #expect(seen.value.contains(14_14))
        let late = try await engine.synthesize(.init(spoken: "The quick brown fox jumps over the lazy dog.", voiceID: Self.voiceID("af_heart")))
        #expect((1.0 ... 6.0).contains(late.audio.duration))
    }

    /// Every stage's load waits on the admission closure — the app's foreground gate — once per
    /// stage, and a closed gate holds the load until it opens.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func everyStageLoadIsAdmittedThroughTheGate() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources())
        let gate = ForegroundGate(isForeground: false)
        let admissions = OSAllocatedUnfairLockBox(0)
        await engine.setLoadAdmission {
            admissions.value += 1
            await gate.waitUntilForeground()
        }
        let preload = Task { try await engine.preload() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(await engine.loadedBuckets.isEmpty)                 // nothing loaded through a closed gate
        gate.set(foreground: true)
        try await preload.value
        try await engine.awaitFullLoad()
        #expect(admissions.value == KokoroCoreMLResources.stageNames().count)
    }
}

extension KokoroCoreMLLoadTests {
    /// A piece cut for the t256 duration model, rendered through a set whose largest is t128 — the
    /// background set — is split before any render, like a piece whose audio overflows its bucket.
    @Test func aPieceTooLongForTheSetIsSplitBeforeItRenders() throws {
        let words = (0 ..< 40).map { KokoroCoreMLEngineTests.word("w\($0)", phonemes: "abcd") }
        var ids: [Int32] = [], owners: [Int] = []
        for index in 0 ..< 40 {
            ids += [1, 2, 3, 4, 0]
            owners += Array(repeating: index, count: 4) + [KokoroCoreMLTimingFold.noOwner]
        }
        // 200 ids: the chunker's own cap makes a 175-id first piece, which is what the set must split.
        let piece = try #require(try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words).first)
        let rendered = OSAllocatedUnfairLockBox<[Int]>([])
        let outcome = try KokoroCoreMLEngine.renderSplittingOnOverflow(piece, isFinal: true, words: words, maxTokens: 128) { attempted in
            rendered.value.append(attempted.ids.count)
            return KokoroCoreMLEngineTests.fakeRenderResult(frames: Array(repeating: 1, count: attempted.ids.count + 2))
        }
        #expect(rendered.value.allSatisfy { $0 + 2 <= 128 })
        #expect(outcome.count >= 2)
        #expect(outcome.map(\.piece.ids.count).reduce(0, +) == piece.ids.count)
    }

    /// With a background set and a placement that says "background", a long sentence renders in
    /// that set's 3 s bucket, in pieces; placed in the foreground it renders in the main set.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func aBackgroundPlacementRendersThroughTheBackgroundSet() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        var options = KokoroCoreMLEngine.Options.default
        options.backgroundComputeUnits = .cpu
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: options)
        let placement = OSAllocatedUnfairLockBox(KokoroCoreMLEngine.RenderPlacement.foreground)
        await engine.setRenderPlacement { placement.value }
        try await engine.preload()
        await engine.awaitBackgroundSet()
        #expect(await engine.hasBackgroundSet)

        let buckets = OSAllocatedUnfairLockBox<[Int]>([])
        await engine.setUtteranceTrace { trace in buckets.value = trace.pieces.map(\.bucketSeconds) }
        placement.value = .background
        let callsBefore = await engine.renderCallCount
        let behind = try await engine.synthesize(.init(spoken: KokoroCoreMLEngineTests.longSentence, voiceID: Self.voiceID("af_heart")))
        let callsAfter = await engine.renderCallCount
        #expect(await engine.lastRenderSet == "background")
        #expect(buckets.value.allSatisfy { $0 == 3 } && buckets.value.count >= 4)
        #expect(behind.audio.duration > 15)
        // Every piece is cut for the 3 s bucket before it renders (`backgroundPieceTokenCount`,
        // the review of 2026-09-11, §5 item 2), so no pipeline call should overflow its bucket and
        // be thrown away: one call per kept piece, not more.
        #expect(callsAfter - callsBefore == buckets.value.count)

        placement.value = .foreground
        _ = try await engine.synthesize(.init(spoken: "The quick brown fox jumps over the lazy dog.", voiceID: Self.voiceID("af_heart")))
        #expect(await engine.lastRenderSet == "main")
    }

    /// A failed background-set load is not final for the session (the review of 2026-09-11, §3 R6):
    /// once the retry window has passed, the next `awaitBackgroundSet()` starts a fresh load, and
    /// it can land the set. `setStageLoader` fakes the first attempt's failure — a real, transient
    /// Core ML failure is not something a test can arrange — and defers to the real loader after
    /// that, so the successful second attempt still proves a real background set works;
    /// `setBackgroundSetLoadRetryInterval` shortens the wait so the suite does not pay the real 30 s.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func aFailedBackgroundSetLoadRetriesAfterTheWindow() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        var options = KokoroCoreMLEngine.Options.default
        options.backgroundComputeUnits = .cpu
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: options)
        await engine.setBackgroundSetLoadRetryInterval(.milliseconds(50))
        let attempts = OSAllocatedUnfairLockBox(0)
        await engine.setStageLoader { compiled, names, computeUnits, window, admission, onStageLoaded in
            attempts.value += 1
            guard attempts.value > 1 else { throw KokoroCoreMLError.stageFailed("fake first attempt") }
            return try await KokoroCoreMLModels.loadStages(
                compiled, names: names, computeUnits: computeUnits, window: window,
                admission: admission, onStageLoaded: onStageLoaded
            )
        }

        try await engine.preload()
        // The first attempt has already run and failed by the time `preload()` returns
        // (`startBackgroundSetLoad` is kicked off, not awaited, but `awaitBackgroundSet` joins it).
        let beforeWindow = await engine.awaitBackgroundSet()
        #expect(beforeWindow == false)
        #expect(await engine.hasBackgroundSet == false)
        #expect(attempts.value == 1)

        try await Task.sleep(for: .milliseconds(80))                // past the shortened retry window
        let afterWindow = await engine.awaitBackgroundSet()
        #expect(afterWindow)
        #expect(await engine.hasBackgroundSet)
        #expect(attempts.value == 2)
    }
}

/// A value the test can read from any task.
final class OSAllocatedUnfairLockBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
