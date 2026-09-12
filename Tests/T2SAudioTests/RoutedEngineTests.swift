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

    /// Streaming is routed like synthesis: the engine that owns the voice answers, in pieces. Uses a
    /// `FakeEngine` that actually streams more than one piece (not `RecordingEngine`, which only ever
    /// gets the protocol's one-piece default) so this test would fail if `RoutedEngine` stopped
    /// forwarding to the routed engine's own `synthesizeStreaming` and fell back to wrapping its own
    /// `synthesize` instead.
    @Test func streamingIsForwardedToTheRoutedEngine() async throws {
        let system = FakeEngine(secondsPerCharacter: 0.1, pieceCount: 2)
        let routed = RoutedEngine(system: system, configuration: { nil }, key: { nil })

        // The system route: the `system:` prefix strips to the bare identifier before forwarding.
        var ordinals: [Int] = []
        for try await chunk in routed.synthesizeStreaming(SynthesisRequest(spoken: "abcdef", voiceID: "system:v")) {
            if case .piece(_, let ordinal, _) = chunk { ordinals.append(ordinal) }
        }
        #expect(ordinals == [0, 1])
        #expect(await system.requests.map(\.voiceID) == ["v"])
    }
    @Test func reportsTheMirrorCountForACloudVoiceAndOneForEverythingElse() throws {
        let configuration = HTTPVoiceConfiguration(
            endpoints: [
                try #require(URL(string: "https://one.example/v1/audio/speech")),
                try #require(URL(string: "https://two.example/v1/audio/speech")),
                try #require(URL(string: "https://three.example/v1/audio/speech")),
            ],
            model: "m", voice: "v", requestRatePerMinute: 60)
        let routed = RoutedEngine(system: RecordingEngine(), configuration: { configuration }, key: { nil })
        let cloud = CloudVoiceID(configuration: configuration, voice: "v").rawValue

        #expect(routed.maxConcurrentRenders(for: cloud) == 3)
        #expect(routed.maxConcurrentRenders(for: "cloud:stale:v") == 1)
        #expect(routed.maxConcurrentRenders(for: "system:com.example.voice") == 1)
        #expect(routed.maxConcurrentRenders(for: KokoroVoiceID(engineID: "kokoro-x", voice: "af_heart").rawValue) == 1)
    }

    /// The fingerprint ignores mirrors, so the engine cache cannot key on it alone: a changed
    /// mirror list builds a new engine, seen here as the new mirror taking its turn. The transport
    /// is this file's own: `TestURLProtocol`'s state is process-wide, and the HTTP engine's suite
    /// runs alongside this one.
    @Test func aChangedMirrorListRebuildsTheCloudEngine() async throws {
        let one = try #require(URL(string: "https://one.example/v1/audio/speech"))
        let two = try #require(URL(string: "https://two.example/v1/audio/speech"))
        let session = MirrorTransport.session()
        let box = ConfigurationBox(HTTPVoiceConfiguration(endpoints: [one], model: "m", voice: "v", requestRatePerMinute: 120))
        let routed = RoutedEngine(system: RecordingEngine(), configuration: { box.value }, key: { "test-key" }, session: session)
        let voiceID = CloudVoiceID(configuration: try #require(box.value), voice: "v").rawValue

        _ = try await routed.synthesize(.init(spoken: "a", voiceID: voiceID))
        box.value = HTTPVoiceConfiguration(endpoints: [one, two], model: "m", voice: "v", requestRatePerMinute: 120)
        _ = try await routed.synthesize(.init(spoken: "b", voiceID: voiceID))      // same fingerprint, new engine: its cursor starts at one
        _ = try await routed.synthesize(.init(spoken: "c", voiceID: voiceID))      // then two

        #expect(MirrorTransport.hosts == ["one.example", "one.example", "two.example"])
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

private final class ConfigurationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: HTTPVoiceConfiguration?
    init(_ value: HTTPVoiceConfiguration?) { stored = value }
    var value: HTTPVoiceConfiguration? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// A transport of this file's own, so it never shares state with `TestURLProtocol` in a suite
/// running alongside: answers one PCM sample to any host and records the hosts in order.
private final class MirrorTransport: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var hostsSeen: [String] = []

    static var hosts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return hostsSeen
    }

    static func session() -> URLSession {
        lock.lock()
        hostsSeen = []
        lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MirrorTransport.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.hostsSeen.append(request.url?.host ?? "")
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "audio/pcm"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([0, 0]))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
