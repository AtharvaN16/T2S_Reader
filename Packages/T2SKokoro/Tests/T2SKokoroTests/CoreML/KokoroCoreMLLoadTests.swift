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
