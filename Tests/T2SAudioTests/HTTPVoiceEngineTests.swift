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

    /// Mirrors serve the same audio, so adding one keeps cached renders; changing the primary is
    /// a new route, as it always was.
    @Test func mirrorsDoNotChangeTheRouteIdentityButThePrimaryDoes() throws {
        let primary = try #require(URL(string: "https://one.example/v1/audio/speech"))
        let mirror = try #require(URL(string: "https://two.example/v1/audio/speech"))
        let alone = HTTPVoiceConfiguration(endpoint: primary, model: "m", voice: "v", requestRatePerMinute: 60)
        let mirrored = HTTPVoiceConfiguration(endpoints: [primary, mirror], model: "m", voice: "v", requestRatePerMinute: 60)
        let swapped = HTTPVoiceConfiguration(endpoints: [mirror, primary], model: "m", voice: "v", requestRatePerMinute: 60)

        #expect(mirrored.fingerprint == alone.fingerprint)
        #expect(swapped.fingerprint != alone.fingerprint)
        #expect(mirrored.endpoint == primary)
    }

    @Test func everyMirrorMustPassTheEndpointRulesAndBeDistinct() throws {
        let good = try #require(URL(string: "https://one.example/v1/audio/speech"))
        let plain = try #require(URL(string: "http://two.example/v1/audio/speech"))
        let leaky = try #require(URL(string: "https://two.example/v1/audio/speech?key=x"))
        for bad in [plain, leaky] {
            let configuration = HTTPVoiceConfiguration(endpoints: [good, bad], model: "m", voice: "v", requestRatePerMinute: 60)
            #expect(throws: HTTPVoiceError.invalidConfiguration) { try configuration.validate() }
        }
        let duplicated = HTTPVoiceConfiguration(endpoints: [good, good], model: "m", voice: "v", requestRatePerMinute: 60)
        #expect(throws: HTTPVoiceError.invalidConfiguration) { try duplicated.validate() }
        let other = try #require(URL(string: "https://two.example/v1/audio/speech"))
        let fine = HTTPVoiceConfiguration(endpoints: [good, other], model: "m", voice: "v", requestRatePerMinute: 60)
        #expect(throws: Never.self) { try fine.validate() }
    }

    /// Four concurrent calls land one on each mirror: the engine's width is its mirror count and
    /// a batch that wide never queues behind itself.
    @Test func spreadsConcurrentRequestsOneToEachMirror() async throws {
        let hosts = ["one.example", "two.example", "three.example", "four.example"]
        let pcm = TestURLProtocol.pcmResponse(samples: [1])
        let session = TestURLProtocol.session(byHost: Dictionary(uniqueKeysWithValues: hosts.map { ($0, pcm) }))
        let configuration = HTTPVoiceConfiguration(
            endpoints: try hosts.map { try #require(URL(string: "https://\($0)/v1/audio/speech")) },
            model: "m", voice: "v", requestRatePerMinute: 60)
        let engine = HTTPVoiceEngine(configuration: configuration, key: { "test-key" }, session: session, limiterSleeper: { _ in })

        #expect(engine.maxConcurrentRenders(for: "cloud:x:v") == 4)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<4 {
                group.addTask { _ = try await engine.synthesize(.init(spoken: "piece \(i)", voiceID: "cloud:x:v")) }
            }
            try await group.waitForAll()
        }
        #expect(Set(TestURLProtocol.allRequests.compactMap { $0.url?.host }) == Set(hosts))
    }

    /// A busy mirror answers 429; the request walks to the next mirror and fails only when every
    /// mirror has refused it, each tried once.
    @Test func aBusyMirrorHandsTheRequestToTheNext() async throws {
        let busy = TestURLProtocol.Response(status: 429, headers: ["Retry-After": "2"], data: Data("{\"detail\":\"Synthesis busy\"}".utf8))
        let fine = TestURLProtocol.pcmResponse(samples: [7])
        let one = try #require(URL(string: "https://one.example/v1/audio/speech"))
        let two = try #require(URL(string: "https://two.example/v1/audio/speech"))
        let configuration = HTTPVoiceConfiguration(endpoints: [one, two], model: "m", voice: "v", requestRatePerMinute: 60)

        let session = TestURLProtocol.session(byHost: ["one.example": busy, "two.example": fine])
        let engine = HTTPVoiceEngine(configuration: configuration, key: { "test-key" }, session: session, limiterSleeper: { _ in })
        let result = try await engine.synthesize(.init(spoken: "x", voiceID: "cloud:x:v"))
        #expect(result.audio.samples.count == 1)
        #expect(TestURLProtocol.allRequests.compactMap { $0.url?.host } == ["one.example", "two.example"])

        let allBusy = TestURLProtocol.session(byHost: ["one.example": busy, "two.example": busy])
        let refused = HTTPVoiceEngine(configuration: configuration, key: { "test-key" }, session: allBusy, limiterSleeper: { _ in })
        await #expect(throws: HTTPVoiceError.rateLimited(retryAfter: 2)) {
            try await refused.synthesize(.init(spoken: "x", voiceID: "cloud:x:v"))
        }
        #expect(TestURLProtocol.allRequests.count == 2)
    }

    /// Text over the request cap is cut at clause boundaries, the pieces sent at once, and their
    /// audio joined in text order whichever mirror answers first.
    @Test func longTextIsSplitAtClausesSentConcurrentlyAndJoinedInOrder() async throws {
        // Three clauses of 170 characters: each fits the 180 cap alone, the whole does not.
        let clauses = (1...3).map { n in "\(n) " + String(repeating: "w", count: 166) + "," }
        let text = clauses.joined(separator: " ")
        // Answer each piece with one sample carrying its leading digit, so the join order shows.
        let session = TestURLProtocol.session { request in
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let input = body?["input"] as? String ?? "0"
            return TestURLProtocol.pcmResponse(samples: [Int16(String(input.prefix(1))) ?? 0])
        }
        let engine = HTTPVoiceEngine(configuration: .example, key: { "test-key" }, session: session, limiterSleeper: { _ in })

        let result = try await engine.synthesize(.init(spoken: text, voiceID: "cloud:x:v"))

        let sent = TestURLProtocol.allRequests.compactMap { request in
            (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])?["input"] as? String
        }
        #expect(sent.count == 3)
        #expect(Set(sent) == Set(clauses))
        #expect(sent.allSatisfy { ($0 as NSString).length <= HTTPVoiceEngine.maxRequestCharacters })
        #expect(result.audio.samples.map { Int16(($0 * 32768).rounded()) } == [1, 2, 3])
        #expect(result.wordTimings.isEmpty)
    }

    /// Text within the cap goes out exactly as it came, untouched by the splitter.
    @Test func shortTextIsSentWhole() async throws {
        let session = TestURLProtocol.session(status: 200, headers: ["Content-Type": "audio/pcm"], body: Data([0, 0]))
        let engine = HTTPVoiceEngine(configuration: .example, key: { "test-key" }, session: session, limiterSleeper: { _ in })
        _ = try await engine.synthesize(.init(spoken: "  Kept, spaces and all.  ", voiceID: "cloud:x:v"))
        let body = try #require(TestURLProtocol.lastRequest?.httpBody)
        let request = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(request?["input"] as? String == "  Kept, spaces and all.  ")
        #expect(TestURLProtocol.allRequests.count == 1)
    }

    /// Every mirror carries at most one of this engine's requests at a time: with four routes the
    /// fifth request waits for a release, and takes the route that was released.
    @Test func theRoutePoolNeverHandsOutABusyMirror() async {
        let pool = HTTPVoiceEngine.RoutePool(count: 4)
        var taken: [Int] = []
        for _ in 0..<4 { taken.append(await pool.acquire()) }
        #expect(Set(taken) == [0, 1, 2, 3])

        let fifth = Task { await pool.acquire() }
        var spins = 0
        while await pool.waitingCount != 1, spins < 10_000 { await Task.yield(); spins += 1 }
        #expect(await pool.waitingCount == 1)                                  // parked: every mirror is busy
        await pool.release(2)
        #expect(await fifth.value == 2)                                        // and takes the one released
        #expect(await pool.waitingCount == 0)
    }

    /// The head utterance the player is waiting on streams in clause-sized pieces, each handed over
    /// the moment it lands, in order — the first sound needs one short render, not the whole line.
    @Test func theStreamingHeadArrivesInPiecesInOrder() async throws {
        let clauses = (1...3).map { n in "\(n) " + String(repeating: "w", count: 70) + "," }      // 74 each: three pieces of ≤ 80
        let text = clauses.joined(separator: " ")
        let session = TestURLProtocol.session { request in
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let input = body?["input"] as? String ?? "0"
            return TestURLProtocol.pcmResponse(samples: [Int16(String(input.prefix(1))) ?? 0])
        }
        let engine = HTTPVoiceEngine(configuration: .example, key: { "test-key" }, session: session, limiterSleeper: { _ in })

        var chunks: [SynthesisChunk] = []
        for try await chunk in engine.synthesizeStreaming(.init(spoken: text, voiceID: "cloud:x:v")) { chunks.append(chunk) }

        #expect(chunks.count == 4)                                                                // three pieces, then finished
        var samples: [Int16] = []
        for (i, chunk) in chunks.prefix(3).enumerated() {
            guard case .piece(let audio, let ordinal, let isLast) = chunk else { Issue.record("piece \(i): \(chunk)"); continue }
            #expect(ordinal == i && isLast == (i == 2))
            samples += audio.samples.map { Int16(($0 * 32768).rounded()) }.filter { $0 != 0 }        // the gap is silence
            if i > 0 { #expect(audio.samples.prefix(Int(0.08 * 24_000)).allSatisfy { $0 == 0 }) }     // 80 ms before every later piece
        }
        #expect(samples == [1, 2, 3])
        guard case .finished(let timings) = chunks[3] else { Issue.record("no finished: \(chunks[3])"); return }
        #expect(timings.isEmpty)
    }

    /// A head that fits one piece streams as the protocol default would: one piece, then finished.
    @Test func aShortHeadStreamsAsOnePiece() async throws {
        let session = TestURLProtocol.session(status: 200, headers: ["Content-Type": "audio/pcm"], body: Data([1, 0]))
        let engine = HTTPVoiceEngine(configuration: .example, key: { "test-key" }, session: session, limiterSleeper: { _ in })
        var chunks: [SynthesisChunk] = []
        for try await chunk in engine.synthesizeStreaming(.init(spoken: "One short line.", voiceID: "cloud:x:v")) { chunks.append(chunk) }
        #expect(chunks.count == 2)
        guard case .piece(_, 0, true) = chunks[0] else { Issue.record("\(chunks)"); return }
        #expect(TestURLProtocol.allRequests.count == 1)
    }

    /// An urgent request — a head piece the player is waiting on — takes the next free mirror ahead
    /// of requests that were already waiting.
    @Test func anUrgentRequestJumpsThePoolsQueue() async {
        let pool = HTTPVoiceEngine.RoutePool(count: 1)
        let held = await pool.acquire()
        let ordinary = Task { await pool.acquire() }
        var spins = 0
        while await pool.waitingCount != 1, spins < 10_000 { await Task.yield(); spins += 1 }
        let urgent = Task { await pool.acquire(urgent: true) }
        while await pool.waitingCount != 2, spins < 20_000 { await Task.yield(); spins += 1 }
        await pool.release(held)
        #expect(await urgent.value == 0)                                                          // the urgent one went first
        await pool.release(0)
        #expect(await ordinary.value == 0)
    }

    /// A mirror that cannot be reached, or answers a server error — a dyno mid-restart — is passed
    /// over for the next one; the line fails only when every mirror is down.
    @Test func aMirrorThatIsDownIsPassedOver() async throws {
        let one = try #require(URL(string: "https://one.example/v1/audio/speech"))
        let two = try #require(URL(string: "https://two.example/v1/audio/speech"))
        let configuration = HTTPVoiceConfiguration(endpoints: [one, two], model: "m", voice: "v", requestRatePerMinute: 60)
        let fine = TestURLProtocol.pcmResponse(samples: [7])

        let unreachable = TestURLProtocol.session(byHost: ["one.example": .unreachable, "two.example": fine])
        let engine = HTTPVoiceEngine(configuration: configuration, key: { "test-key" }, session: unreachable, limiterSleeper: { _ in })
        #expect(try await engine.synthesize(.init(spoken: "x", voiceID: "cloud:x:v")).audio.samples.count == 1)
        #expect(TestURLProtocol.allRequests.compactMap { $0.url?.host } == ["one.example", "two.example"])

        let restarting = TestURLProtocol.session(byHost: ["one.example": TestURLProtocol.Response(status: 503, headers: [:], data: Data("<html>".utf8)), "two.example": fine])
        let engine2 = HTTPVoiceEngine(configuration: configuration, key: { "test-key" }, session: restarting, limiterSleeper: { _ in })
        #expect(try await engine2.synthesize(.init(spoken: "x", voiceID: "cloud:x:v")).audio.samples.count == 1)
        #expect(TestURLProtocol.allRequests.compactMap { $0.url?.host } == ["one.example", "two.example"])

        let allDown = TestURLProtocol.session(byHost: ["one.example": .unreachable, "two.example": .unreachable])
        let engine3 = HTTPVoiceEngine(configuration: configuration, key: { "test-key" }, session: allDown, limiterSleeper: { _ in })
        await #expect(throws: HTTPVoiceError.transport("request failed")) {
            try await engine3.synthesize(.init(spoken: "x", voiceID: "cloud:x:v"))
        }
        #expect(TestURLProtocol.allRequests.count == 2)
    }

    /// A rejected key is the reader's to fix, not a mirror's fault: it is never walked.
    @Test func aRejectedKeyIsNotWalked() async throws {
        let one = try #require(URL(string: "https://one.example/v1/audio/speech"))
        let two = try #require(URL(string: "https://two.example/v1/audio/speech"))
        let configuration = HTTPVoiceConfiguration(endpoints: [one, two], model: "m", voice: "v", requestRatePerMinute: 60)
        let session = TestURLProtocol.session(byHost: ["one.example": TestURLProtocol.Response(status: 401, headers: [:], data: Data()), "two.example": TestURLProtocol.pcmResponse(samples: [7])])
        let engine = HTTPVoiceEngine(configuration: configuration, key: { "test-key" }, session: session, limiterSleeper: { _ in })
        await #expect(throws: HTTPVoiceError.server(status: 401, message: "key rejected")) {
            try await engine.synthesize(.init(spoken: "x", voiceID: "cloud:x:v"))
        }
        #expect(TestURLProtocol.allRequests.count == 1)
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
    struct Response: Sendable {
        var status: Int
        var headers: [String: String]
        var data: Data

        /// A host that cannot be reached at all: the load fails with a connection error, as a dyno
        /// mid-restart does.
        static let unreachable = Response(status: 0, headers: [:], data: Data())
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var response = Response(status: 500, headers: [:], data: Data())
    /// Answers by host when set; a host with no entry gets `response`.
    nonisolated(unsafe) private static var responsesByHost: [String: Response] = [:]
    /// Answers from the request itself when set; wins over the host table.
    nonisolated(unsafe) private static var responder: (@Sendable (URLRequest) -> Response)?
    nonisolated(unsafe) private static var capturedRequest: URLRequest?
    nonisolated(unsafe) private static var capturedRequests: [URLRequest] = []

    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequest
    }

    /// Every request since the session was made, in arrival order.
    static var allRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    static func session(status: Int, headers: [String: String] = [:], json: String) -> URLSession {
        session(status: status, headers: headers, body: Data(json.utf8))
    }

    static func session(status: Int, headers: [String: String] = [:], body: Data) -> URLSession {
        session(byHost: [:], fallback: Response(status: status, headers: headers, data: body))
    }

    /// One answer per host; `fallback` answers any host not listed.
    static func session(byHost: [String: Response], fallback: Response = Response(status: 500, headers: [:], data: Data())) -> URLSession {
        reset(response: fallback, byHost: byHost, responder: nil)
        return make()
    }

    /// An answer computed from each request, for tests that need to tell pieces apart by body.
    static func session(answering responder: @escaping @Sendable (URLRequest) -> Response) -> URLSession {
        reset(response: Response(status: 500, headers: [:], data: Data()), byHost: [:], responder: responder)
        return make()
    }

    /// Raw 16-bit little-endian PCM at 24 kHz, the pilot server's answer.
    static func pcmResponse(samples: [Int16], status: Int = 200) -> Response {
        var data = Data()
        for value in samples { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        return Response(status: status, headers: ["Content-Type": "audio/pcm"], data: data)
    }

    private static func reset(response: Response, byHost: [String: Response], responder: (@Sendable (URLRequest) -> Response)?) {
        lock.lock()
        self.response = response
        responsesByHost = byHost
        self.responder = responder
        capturedRequest = nil
        capturedRequests = []
        lock.unlock()
    }

    private static func make() -> URLSession {
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
        Self.capturedRequests.append(captured)
        let response = Self.responder?(captured)
            ?? captured.url?.host.flatMap { Self.responsesByHost[$0] }
            ?? Self.response
        Self.lock.unlock()

        if response.status == 0 {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
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
