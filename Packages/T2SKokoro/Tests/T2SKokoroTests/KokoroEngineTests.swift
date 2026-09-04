import Foundation
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// Serialized: the model-backed tests each drive MLX on the GPU with a 327 MB model loaded, and
/// running them at the same time would measure contention rather than the engine.
@Suite(.serialized) struct KokoroEngineTests {
    /// An engine over URLs that do not exist. Every check `synthesize` makes before it loads the
    /// model can be tested through it, on any machine, in microseconds.
    static func engineWithoutResources() -> KokoroEngine {
        let directory = URL(fileURLWithPath: "/nonexistent/T2SKokoroTests", isDirectory: true)
        return KokoroEngine(resources: KokoroResources.Located(
            model: directory.appending(path: KokoroResources.modelFileName),
            voices: directory.appending(path: KokoroResources.voicesFileName)
        ))
    }

    /// A fresh engine over the installed model. Per test rather than shared, so each model-backed
    /// test loads for itself and MLX never holds two models at once.
    static func engineWithRealResources(gpuCacheLimitBytes: Int? = nil) throws -> KokoroEngine {
        KokoroTestSupport.locatePackageResourceBundles()
        return KokoroEngine(resources: try KokoroResources.locate(in: KokoroResources.developmentDirectory).get(),
                            gpuCacheLimitBytes: gpuCacheLimitBytes)
    }

    static func voiceID(_ voice: String) -> String {
        KokoroVoiceID(engineID: KokoroEngine.identity, voice: voice).rawValue
    }

    // MARK: Identity

    @Test func identityNamesTheWeightsTheRuntimeAndTheG2P() {
        #expect(KokoroEngine.identity == "kokoro-4e9ecdf0-mlx-misaki1.0.6")
        #expect(Self.engineWithoutResources().engineID == KokoroEngine.identity)
    }

    // MARK: Checks that happen before anything is loaded

    @Test(arguments: [
        "kokoro:other-engine:af_heart",     // Kokoro, but not these weights
        "system:x",                         // the system route
        "af_heart",                         // a bare voice name
    ])
    func refusesAVoiceIdentityThatIsNotThisEngine(voiceID: String) async {
        let engine = Self.engineWithoutResources()
        await #expect(throws: KokoroEngineError.voiceNotForThisEngine(voiceID)) {
            try await engine.synthesize(.init(spoken: "Hello.", voiceID: voiceID))
        }
    }

    @Test func refusesTextWithNothingToSpeak() async {
        let engine = Self.engineWithoutResources()
        await #expect(throws: SynthesisError.failed("nothing to speak")) {
            try await engine.synthesize(.init(spoken: "   ", voiceID: Self.voiceID("af_heart")))
        }
    }

    /// The voice table is read before the model, and it is the only one of the two whose absence the
    /// library reports — so a missing resource directory fails here, in microseconds, with the error
    /// the user is shown, rather than deep inside MLX.
    @Test func reportsVoiceDataItCannotRead() async {
        let engine = Self.engineWithoutResources()
        await #expect(throws: KokoroEngineError.voicesUnreadable) {
            try await engine.synthesize(.init(spoken: "Hello.", voiceID: Self.voiceID("af_heart")))
        }
    }

    /// A render cancelled before it reaches the front of the engine's queue must not load a model and
    /// synthesize for seconds: the scheduler cancels pending work on stop, and the actor's queue is
    /// serial, so the next real render would wait behind it.
    @Test func aCancelledRenderLeavesTheQueueWithoutLoadingAnything() async {
        let engine = Self.engineWithoutResources()
        let render = Task {
            // Deterministic: the render is only attempted once this task is already cancelled.
            while !Task.isCancelled { await Task.yield() }
            return try await engine.synthesize(.init(spoken: "Hello.", voiceID: Self.voiceID("af_heart")))
        }
        render.cancel()
        await #expect(throws: CancellationError.self) { _ = try await render.value }
    }

    // MARK: The real model

    @Test(.enabled(if: KokoroTestSupport.haveRealFiles))
    func synthesizesAnAmericanSentenceAtThePipelineRate() async throws {
        let engine = try Self.engineWithRealResources()
        let loadStarted = Date()
        try await engine.preload()
        let loadSeconds = Date().timeIntervalSince(loadStarted)

        let synthesisStarted = Date()
        let result = try await engine.synthesize(.init(
            spoken: "The quick brown fox jumps over the lazy dog.",
            voiceID: Self.voiceID("af_heart")
        ))
        let synthesisSeconds = Date().timeIntervalSince(synthesisStarted)

        #expect(result.audio.sampleRate == 24_000)
        #expect((1.0 ... 6.0).contains(result.audio.duration))
        // Hoisted: `#expect` decomposes the expression and cannot see through `allSatisfy`'s `rethrows`.
        let everySampleIsFinite = result.audio.samples.allSatisfy(\.isFinite)
        #expect(everySampleIsFinite)
        #expect(Self.rms(result.audio.samples) > 0.01)
        // The §7.4 gate is open (2026-09-04), and kokoro-ios does populate `start_ts`/`end_ts`, so
        // this route now returns timings too. What is asserted is the shape the highlighter needs;
        // the accuracy bar was measured on the Core ML route, not this one. Asserted first because
        // every check below it holds vacuously on an empty array.
        #expect(!result.wordTimings.isEmpty)
        #expect(result.wordTimings.map(\.start) == result.wordTimings.map(\.start).sorted())
        #expect((result.wordTimings.last?.end ?? 0) <= result.audio.duration + 0.001)

        // The plan takes its real-time factor from the 17 Pro; this line records the Mac's, which is
        // the only number this task can measure. Hidden by `scripts/test-kokoro.sh`'s output filter.
        print(String(format: "kokoro measurement: load %.2fs, synthesis %.2fs for %.2fs of audio (RTF %.3f)",
                     loadSeconds, synthesisSeconds, result.audio.duration,
                     synthesisSeconds / result.audio.duration))
    }

    @Test(.enabled(if: KokoroTestSupport.haveRealFiles))
    func synthesizesThroughTheBritishVoicePath() async throws {
        let engine = try Self.engineWithRealResources()
        let result = try await engine.synthesize(.init(
            spoken: "The quick brown fox jumps over the lazy dog.",
            voiceID: Self.voiceID("bf_emma")
        ))
        #expect(result.audio.duration > 0.5)
        #expect(Self.rms(result.audio.samples) > 0.01)
    }

    /// The memory policy of `KokoroRuntimeDecision.gpuCacheLimitBytes`: MLX's buffer cache grows to
    /// whatever the device allows unless it is capped, which is what puts a long render over the
    /// jetsam limit on a phone.
    @Test(.enabled(if: KokoroTestSupport.haveRealFiles))
    func appliesTheGPUCacheLimitWhenItLoads() async throws {
        let limit = 96 * 1024 * 1024
        let engine = try Self.engineWithRealResources(gpuCacheLimitBytes: limit)
        try await engine.preload()
        #expect(KokoroEngine.currentGPUCacheLimitBytes == limit)
    }

    @Test(.enabled(if: KokoroTestSupport.haveRealFiles))
    func refusesAVoiceThatIsNotInTheVoiceTable() async throws {
        let engine = try Self.engineWithRealResources()
        await #expect(throws: KokoroEngineError.unknownVoice("zz_nobody")) {
            try await engine.synthesize(.init(spoken: "Hello.", voiceID: Self.voiceID("zz_nobody")))
        }
    }

    private static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(samples.count)).squareRoot()
    }
}
