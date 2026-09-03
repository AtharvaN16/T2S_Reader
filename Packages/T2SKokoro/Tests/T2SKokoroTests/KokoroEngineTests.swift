import Foundation
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// Serialized: the model-backed tests each drive MLX on the GPU with a 327 MB model loaded, and
/// running them at the same time would measure contention rather than the engine.
@Suite(.serialized) struct KokoroEngineTests {
    /// The real files are installed by `scripts/fetch-kokoro-model.sh`; CI has neither.
    static let haveRealFiles = (try? KokoroResources.locate(in: KokoroResources.developmentDirectory).get()) != nil

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
    static func engineWithRealResources() throws -> KokoroEngine {
        _ = packageResourceBundlesLocated
        return KokoroEngine(resources: try KokoroResources.locate(in: KokoroResources.developmentDirectory).get())
    }

    /// Only ever passed to `Bundle(for:)`, to find the `.xctest` bundle this code was loaded from.
    private final class TestBundleFinder {}

    /// KokoroSwift, MisakiSwift and mlx-swift each ship a SwiftPM resource bundle (the lexicons, the
    /// Metal library). Xcode stages all of them in this `.xctest` bundle's `Resources`, but the
    /// `Bundle.module` accessor generated inside a package *framework* only looks in `Bundle.main` —
    /// the `xctest` tool — and in the framework's own `Resources`, and traps with
    /// "unable to find bundle named KokoroSwift_KokoroSwift" when it finds neither.
    /// `PACKAGE_RESOURCE_BUNDLE_PATH` is the override SwiftPM generates for exactly this case, and
    /// `xcodebuild` forwards no environment of its own to the test process, so it is set here — once,
    /// before any test touches KokoroSwift, which every model-backed test does through
    /// ``engineWithRealResources()``. The app needs none of this: linked into an app the bundles are
    /// in `Bundle.main.resourceURL`, which is the accessor's first candidate.
    private static let packageResourceBundlesLocated: Void = {
        guard ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] == nil,
              let resources = Bundle(for: TestBundleFinder.self).resourceURL
        else { return }
        setenv("PACKAGE_RESOURCE_BUNDLE_PATH", resources.path(percentEncoded: false), 1)
    }()

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

    // MARK: The real model

    @Test(.enabled(if: KokoroEngineTests.haveRealFiles))
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
        // Spec §7.4 gate: unproven until the 17 Pro timing fixture exists (plan adjustment 5).
        #expect(result.wordTimings.isEmpty)

        // The plan takes its real-time factor from the 17 Pro; this line records the Mac's, which is
        // the only number this task can measure. Hidden by `scripts/test-kokoro.sh`'s output filter.
        print(String(format: "kokoro measurement: load %.2fs, synthesis %.2fs for %.2fs of audio (RTF %.3f)",
                     loadSeconds, synthesisSeconds, result.audio.duration,
                     synthesisSeconds / result.audio.duration))
    }

    @Test(.enabled(if: KokoroEngineTests.haveRealFiles))
    func synthesizesThroughTheBritishVoicePath() async throws {
        let engine = try Self.engineWithRealResources()
        let result = try await engine.synthesize(.init(
            spoken: "The quick brown fox jumps over the lazy dog.",
            voiceID: Self.voiceID("bf_emma")
        ))
        #expect(result.audio.duration > 0.5)
        #expect(Self.rms(result.audio.samples) > 0.01)
    }

    @Test(.enabled(if: KokoroEngineTests.haveRealFiles))
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
