import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@Suite(.serialized) struct RoutedEngineTests {
    @Test func routesAMatchingCloudIdentityToTheCloudRoute() async throws {
        let configuration = HTTPVoiceConfiguration(
            endpoint: try #require(URL(string: "https://voice.example/v1/audio/speech")),
            model: "user-model",
            voice: "provider-voice",
            requestRatePerMinute: 60
        )
        let system = RecordingEngine()
        let routed = RoutedEngine(
            system: system,
            configuration: { configuration },
            key: { nil }
        )

        let voiceID = CloudVoiceID(configuration: configuration, voice: "provider-voice").rawValue
        await #expect(throws: HTTPVoiceError.missingKey) {
            try await routed.synthesize(.init(spoken: "Hello", voiceID: voiceID))
        }

        #expect(await system.requests.isEmpty)
    }

    @Test func refusesAStaleCloudIdentityAndRoutesSystemIDs() async throws {
        let configuration = HTTPVoiceConfiguration.example
        let system = RecordingEngine()
        let routed = RoutedEngine(system: system, configuration: { configuration }, key: { "test-key" })

        await #expect(throws: HTTPVoiceError.notConfigured) {
            try await routed.synthesize(.init(spoken: "x", voiceID: "cloud:stale:provider-voice"))
        }

        _ = try await routed.synthesize(.init(spoken: "x", voiceID: "system:com.example.voice"))
        #expect(await system.requests == [.init(spoken: "x", voiceID: "com.example.voice")])
    }

    @Test func routesAMatchingKokoroIdentityToTheKokoroEngineUnchanged() async throws {
        let identity = "kokoro-4e9ecdf0-mlx-misaki1.0.6"
        let system = RecordingEngine()
        let kokoro = RecordingEngine(engineID: identity)
        let routed = RoutedEngine(system: system, configuration: { nil }, key: { nil }, kokoro: kokoro)

        let voiceID = KokoroVoiceID(engineID: identity, voice: "af_heart").rawValue
        _ = try await routed.synthesize(.init(spoken: "Hello", voiceID: voiceID))

        // The engine parses the voice out of the ID itself, so the request must arrive unchanged.
        #expect(await kokoro.requests == [.init(spoken: "Hello", voiceID: voiceID)])
        #expect(await system.requests.isEmpty)
    }

    @Test func refusesAKokoroIdentityFromAnotherBuildAndOneWithNoKokoroEngine() async throws {
        let identity = "kokoro-4e9ecdf0-mlx-misaki1.0.6"
        let other = "kokoro-00000000-mlx-misaki1.0.6"
        let system = RecordingEngine()
        let kokoro = RecordingEngine(engineID: identity)
        let routed = RoutedEngine(system: system, configuration: { nil }, key: { nil }, kokoro: kokoro)

        await #expect(throws: KokoroRouteError.unavailable(engineID: other)) {
            try await routed.synthesize(.init(spoken: "x", voiceID: KokoroVoiceID(engineID: other, voice: "af_heart").rawValue))
        }

        let withoutKokoro = RoutedEngine(system: system, configuration: { nil }, key: { nil })
        await #expect(throws: KokoroRouteError.unavailable(engineID: identity)) {
            try await withoutKokoro.synthesize(.init(spoken: "x", voiceID: KokoroVoiceID(engineID: identity, voice: "af_heart").rawValue))
        }

        // A Kokoro ID never silently degrades to a different voice mid-book (spec §6).
        #expect(await kokoro.requests.isEmpty)
        #expect(await system.requests.isEmpty)
    }

    @Test func systemAndBareVoiceIDsStillReachTheSystemEngineBesideAKokoroRoute() async throws {
        let system = RecordingEngine()
        let kokoro = RecordingEngine(engineID: "kokoro-4e9ecdf0-mlx-misaki1.0.6")
        let routed = RoutedEngine(system: system, configuration: { nil }, key: { nil }, kokoro: kokoro)

        _ = try await routed.synthesize(.init(spoken: "a", voiceID: "system:com.example.voice"))
        _ = try await routed.synthesize(.init(spoken: "b", voiceID: "default"))

        #expect(await system.requests == [.init(spoken: "a", voiceID: "com.example.voice"),
                                          .init(spoken: "b", voiceID: "default")])
        #expect(await kokoro.requests.isEmpty)
    }

    @Test func routesEachKokoroIdentityToItsOwnEngineUnchanged() async throws {
        let coreML = "kokoro-coreml-2e878c6a-misaki1.0.6"
        let mlx = "kokoro-4e9ecdf0-mlx-misaki1.0.6"
        let system = RecordingEngine()
        let coreMLEngine = RecordingEngine(engineID: coreML)
        let mlxEngine = RecordingEngine(engineID: mlx)
        let routed = RoutedEngine(system: system, kokoro: [coreMLEngine, mlxEngine],
                                  configuration: { nil }, key: { nil })

        let coreMLVoice = KokoroVoiceID(engineID: coreML, voice: "af_heart").rawValue
        let mlxVoice = KokoroVoiceID(engineID: mlx, voice: "bf_emma").rawValue
        _ = try await routed.synthesize(.init(spoken: "a", voiceID: coreMLVoice))
        _ = try await routed.synthesize(.init(spoken: "b", voiceID: mlxVoice))

        // Two runtimes render different audio for the same words, so an ID reaches its own engine and
        // only its own: the identity inside the ID is the render identity (spec §5).
        #expect(await coreMLEngine.requests == [.init(spoken: "a", voiceID: coreMLVoice)])
        #expect(await mlxEngine.requests == [.init(spoken: "b", voiceID: mlxVoice)])
        #expect(await system.requests.isEmpty)
    }

    @Test func refusesAKokoroIdentityNoRegisteredEngineServes() async throws {
        let coreML = "kokoro-coreml-2e878c6a-misaki1.0.6"
        let mlx = "kokoro-4e9ecdf0-mlx-misaki1.0.6"
        let stranger = "kokoro-00000000-coreml-misaki1.0.6"
        let system = RecordingEngine()
        let coreMLEngine = RecordingEngine(engineID: coreML)
        let mlxEngine = RecordingEngine(engineID: mlx)
        let routed = RoutedEngine(system: system, kokoro: [coreMLEngine, mlxEngine],
                                  configuration: { nil }, key: { nil })

        await #expect(throws: KokoroRouteError.unavailable(engineID: stranger)) {
            try await routed.synthesize(
                .init(spoken: "x", voiceID: KokoroVoiceID(engineID: stranger, voice: "af_heart").rawValue))
        }

        // Never handed to whichever Kokoro engine happens to be loaded (spec §6).
        #expect(await coreMLEngine.requests.isEmpty)
        #expect(await mlxEngine.requests.isEmpty)
        #expect(await system.requests.isEmpty)
    }
}

private actor RecordingEngine: SynthesisEngine {
    nonisolated let engineID: String
    private(set) var requests: [SynthesisRequest] = []

    init(engineID: String = "recording") { self.engineID = engineID }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        requests.append(request)
        return SynthesisResult(audio: PCMAudio(sampleRate: 24_000, samples: []), wordTimings: [])
    }
}
