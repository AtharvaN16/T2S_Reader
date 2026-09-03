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
}

private actor RecordingEngine: SynthesisEngine {
    nonisolated let engineID = "recording"
    private(set) var requests: [SynthesisRequest] = []

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        requests.append(request)
        return SynthesisResult(audio: PCMAudio(sampleRate: 24_000, samples: []), wordTimings: [])
    }
}
