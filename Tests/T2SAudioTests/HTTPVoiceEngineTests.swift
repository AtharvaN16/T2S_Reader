import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@Suite(.serialized) struct HTTPVoiceEngineTests {
    @Test func postsBearerKeyAndDecodesPCMResponse() async throws {
        let session = TestURLProtocol.session(status: 200, json: """
        {"audio":"","sample_rate":24000,"word_timings":[]}
        """)
        let engine = HTTPVoiceEngine(
            configuration: .init(
                endpoint: try #require(URL(string: "https://voice.example/v1/audio/speech")),
                model: "user-model",
                voice: "provider-voice",
                requestRatePerMinute: 60
            ),
            key: { "test-key" },
            session: session
        )

        let result = try await engine.synthesize(.init(spoken: "Hello", voiceID: "cloud:v1:voice"))

        #expect(result.audio.sampleRate == 24_000 && result.audio.samples.isEmpty)
        #expect(TestURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let body = try #require(TestURLProtocol.lastRequest?.httpBody)
        let request = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(request?["model"] as? String == "user-model")
        #expect(request?["voice"] as? String == "voice")
        #expect(request?["response_format"] as? String == "pcm")
        // OpenAI rejects fields it does not know: exactly its four, nothing else.
        #expect(Set((request ?? [:]).keys) == ["model", "input", "voice", "response_format"])
    }

    /// What `https://api.openai.com/v1/audio/speech` actually returns for `response_format: "pcm"`:
    /// raw 16-bit little-endian mono at 24 kHz, no envelope, no timings.
    @Test func decodesOpenAIsRawSixteenBitPCM() async throws {
        var pcm = Data()
        for value in [Int16(0), 16384, -16384, Int16.max, Int16.min] {
            withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) }
        }
        let session = TestURLProtocol.session(status: 200, headers: ["Content-Type": "audio/pcm"], body: pcm)
        let engine = HTTPVoiceEngine(configuration: .example, key: { "test-key" }, session: session)

        let result = try await engine.synthesize(.init(spoken: "Hello", voiceID: "cloud:v1:alloy"))

        #expect(result.audio.sampleRate == 24_000)
        #expect(result.audio.samples.count == 5)
        #expect(result.audio.samples[0] == 0)
        #expect(abs(result.audio.samples[1] - 0.5) < 0.001)
        #expect(abs(result.audio.samples[2] + 0.5) < 0.001)
        #expect(result.audio.samples[3] < 1 && result.audio.samples[3] > 0.999)
        #expect(result.audio.samples[4] == -1)
        #expect(result.wordTimings.isEmpty)
        let body = try #require(TestURLProtocol.lastRequest?.httpBody)
        let request = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(request?["voice"] as? String == "alloy")
    }

    @Test func anOddByteCountOfRawPCMIsMalformed() async {
        let session = TestURLProtocol.session(status: 200, headers: ["Content-Type": "audio/pcm"], body: Data([1, 2, 3]))
        let engine = HTTPVoiceEngine(configuration: .example, key: { "test-key" }, session: session)
        await #expect(throws: HTTPVoiceError.malformedResponse) {
            try await engine.synthesize(.init(spoken: "x", voiceID: "cloud:v1:v"))
        }
    }

    /// A proxy that labels its JSON as such, and one that forgets the header, both decode as JSON.
    @Test func aJSONBodyWithoutAContentTypeStillDecodesAsJSON() async throws {
        let session = TestURLProtocol.session(status: 200, headers: [:], json: """
        {"audio":"","sample_rate":24000}
        """)
        let engine = HTTPVoiceEngine(configuration: .example, key: { "test-key" }, session: session)
        let result = try await engine.synthesize(.init(spoken: "x", voiceID: "cloud:v1:v"))
        #expect(result.audio.samples.isEmpty)
    }

    @Test func statusAndMissingKeySurfaceActionableErrors() async {
        let missing = HTTPVoiceEngine(configuration: .example, key: { nil }, session: .shared)
        await #expect(throws: HTTPVoiceError.self) {
            try await missing.synthesize(.init(spoken: "x", voiceID: "cloud:v1:v"))
        }

        let rejected = HTTPVoiceEngine(
            configuration: .example,
            key: { "test-key" },
            session: TestURLProtocol.session(status: 429, headers: ["Retry-After": "12"], json: "{\"error\":\"slow down\"}")
        )
        await #expect(throws: HTTPVoiceError.rateLimited(retryAfter: 12)) {
            try await rejected.synthesize(.init(spoken: "x", voiceID: "cloud:v1:v"))
        }

        let invalidKey = HTTPVoiceEngine(
            configuration: .example,
            key: { "test-key" },
            session: TestURLProtocol.session(status: 401, json: "{\"error\":\"invalid key\"}")
        )
        await #expect(throws: HTTPVoiceError.server(status: 401, message: "key rejected")) {
            try await invalidKey.synthesize(.init(spoken: "x", voiceID: "cloud:v1:v"))
        }
        #expect(HTTPVoiceError.server(status: 401, message: "key rejected").description.contains("key was rejected"))
    }

    @Test func rejectsMalformedAndUnsafeResponses() async {
        let engine = HTTPVoiceEngine(
            configuration: .example,
            key: { "test-key" },
            session: TestURLProtocol.session(status: 200, json: "{\"audio\":\"not base64\",\"sample_rate\":24000}")
        )

        await #expect(throws: HTTPVoiceError.malformedResponse) {
            try await engine.synthesize(.init(spoken: "x", voiceID: "cloud:v1:v"))
        }
    }

    @Test func rejectsAnEndpointThatCouldPersistAKeyInItsURL() throws {
        let configuration = HTTPVoiceConfiguration(
            endpoint: try #require(URL(string: "https://voice.example/v1/audio?api_key=not-allowed")),
            model: "user-model",
            voice: "provider-voice",
            requestRatePerMinute: 60
        )

        #expect(throws: HTTPVoiceError.invalidConfiguration) { try configuration.validate() }
    }

    @Test func rateLimiterSpacesRequestsAndHonoursRetryAfter() async {
        let clock = TestRateClock()
        let limiter = RequestRateLimiter(requestsPerMinute: 60, now: { clock.now }, sleeper: { seconds in
            clock.recordSleep(seconds)
        })

        await limiter.wait()
        await limiter.wait()
        await limiter.deferUntil(seconds: 5)
        await limiter.wait()

        #expect(clock.sleeps == [0, 1, 5])
    }
}

final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Response {
        var status: Int
        var headers: [String: String]
        var data: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var response = Response(status: 500, headers: [:], data: Data())
    nonisolated(unsafe) private static var capturedRequest: URLRequest?

    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequest
    }

    static func session(status: Int, headers: [String: String] = [:], json: String) -> URLSession {
        session(status: status, headers: headers, body: Data(json.utf8))
    }

    static func session(status: Int, headers: [String: String] = [:], body: Data) -> URLSession {
        lock.lock()
        response = Response(status: status, headers: headers, data: body)
        capturedRequest = nil
        lock.unlock()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        var captured = request
        if captured.httpBody == nil {
            captured.httpBody = Self.readBody(from: captured.httpBodyStream)
        }
        Self.capturedRequest = captured
        let response = Self.response
        Self.lock.unlock()

        let urlResponse = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil,
                                          headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: urlResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class TestRateClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []
    let now = Date(timeIntervalSinceReferenceDate: 0)

    var sleeps: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func recordSleep(_ seconds: TimeInterval) {
        lock.lock()
        values.append(seconds)
        lock.unlock()
    }
}
