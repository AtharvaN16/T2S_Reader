import CryptoKit
import Foundation
import T2SCore

/// Non-secret configuration for the OpenAI-compatible cloud voice contract. The endpoint is
/// deliberately user supplied: T2S does not run a proxy or provider account (spec §1.1).
public struct HTTPVoiceConfiguration: Hashable, Sendable {
    /// `pcm-v2` (2026-09-10): the request is OpenAI's own — `response_format: "pcm"`, nothing the
    /// API would reject — and the answer is raw 16-bit PCM, or a proxy's JSON. The `v1` contract
    /// asked for `pcm_f32le` with `sample_rate` and `timestamps` fields no real provider accepts,
    /// so it never rendered anything outside the tests.
    public static let formatVersion = "pcm-v2"

    /// The primary first, then its mirrors: identical deployments that serve the same audio for
    /// the same request. Never empty.
    public let endpoints: [URL]
    public let model: String
    public let voice: String
    /// Applies to each endpoint separately.
    public let requestRatePerMinute: Int

    public init(endpoints: [URL], model: String, voice: String, requestRatePerMinute: Int) {
        precondition(!endpoints.isEmpty, "a cloud route needs at least one endpoint")
        self.endpoints = endpoints
        self.model = model.trimmed
        self.voice = voice.trimmed
        self.requestRatePerMinute = requestRatePerMinute
    }

    public init(endpoint: URL, model: String, voice: String, requestRatePerMinute: Int) {
        self.init(endpoints: [endpoint], model: model, voice: voice, requestRatePerMinute: requestRatePerMinute)
    }

    /// The primary. Its identity is the route's; a mirror is interchangeable with it.
    public var endpoint: URL { endpoints[0] }

    /// A non-secret identity for rendered audio. Rate limiting is intentionally excluded: changing
    /// it does not change a provider's PCM output, while endpoint/model/voice/format do. Mirrors
    /// are excluded for the same reason: they serve the primary's output.
    public var fingerprint: String {
        let material = [Self.formatVersion, Self.canonical(endpoint), model.trimmed, voice.trimmed].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func validate() throws {
        guard !model.isEmpty, !voice.isEmpty, (1...120).contains(requestRatePerMinute) else { throw HTTPVoiceError.invalidConfiguration }
        for endpoint in endpoints { try Self.validate(endpoint: endpoint) }
        guard Set(endpoints.map(Self.canonical)).count == endpoints.count else { throw HTTPVoiceError.invalidConfiguration }
    }

    private static func validate(endpoint: URL) throws {
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { throw HTTPVoiceError.invalidConfiguration }
    }

    private static func canonical(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    public static let example = HTTPVoiceConfiguration(
        endpoint: URL(string: "https://voice.example/v1/audio/speech")!,
        model: "example-model",
        voice: "example-voice",
        requestRatePerMinute: 60
    )
}

/// Stable, non-secret cloud voice route. It is carried in `SynthesisRequest.voiceID`, so the
/// existing `RenderKey` structurally invalidates audio when a cloud rendering setting changes.
public struct CloudVoiceID: Hashable, Sendable {
    public let fingerprint: String
    public let voice: String
    public let rawValue: String

    public init(configuration: HTTPVoiceConfiguration, voice: String) {
        fingerprint = configuration.fingerprint
        self.voice = voice
        rawValue = "cloud:\(fingerprint):\(voice)"
    }

    public init?(rawValue: String) {
        guard rawValue.hasPrefix("cloud:") else { return nil }
        let remainder = rawValue.dropFirst("cloud:".count)
        guard let separator = remainder.firstIndex(of: ":") else { return nil }
        let fingerprint = String(remainder[..<separator])
        let voice = String(remainder[remainder.index(after: separator)...])
        guard !fingerprint.isEmpty, !voice.trimmed.isEmpty else { return nil }
        self.fingerprint = fingerprint
        self.voice = voice
        self.rawValue = rawValue
    }
}

public enum HTTPVoiceError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case notConfigured
    case missingKey
    case invalidConfiguration
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int, message: String)
    case malformedResponse
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "This cloud voice is no longer configured. Choose it again in Cloud voices."
        case .missingKey:
            return "Add an API key in Cloud voices to use this voice."
        case .invalidConfiguration:
            return "Check the Cloud voices endpoint, model, voice, and rate limit."
        case .rateLimited(let retryAfter):
            if let retryAfter { return "Your provider is rate limiting requests. Try again in \(Int(retryAfter.rounded(.up))) seconds." }
            return "Your provider is rate limiting requests. Try again shortly."
        case .server(let status, _):
            if status == 401 || status == 403 { return "Your cloud voice key was rejected. Check it in Cloud voices." }
            return "Your cloud voice provider rejected this request (HTTP \(status))."
        case .malformedResponse:
            return "Your cloud voice provider returned unsupported audio."
        case .transport:
            return "Couldn’t reach your cloud voice provider. Check your connection and try again."
        }
    }

    public var description: String { errorDescription ?? "Cloud voice request failed." }
}

/// Serializes request starts without ever blocking the main actor. A 429 delays all later starts
/// until the provider's `Retry-After` interval has elapsed.
public actor RequestRateLimiter {
    public typealias Now = @Sendable () -> Date
    public typealias Sleeper = @Sendable (TimeInterval) async -> Void

    private let minimumInterval: TimeInterval
    private let now: Now
    private let sleeper: Sleeper
    private var nextStart: Date?

    public init(requestsPerMinute: Int, now: @escaping Now = Date.init,
                sleeper: @escaping Sleeper = { seconds in
                    guard seconds > 0 else { return }
                    try? await Task.sleep(for: .seconds(seconds))
                }) {
        minimumInterval = 60 / Double(max(1, requestsPerMinute))
        self.now = now
        self.sleeper = sleeper
    }

    /// Reserves this request's start before sleeping so concurrent callers cannot take the same
    /// slot while this actor is suspended.
    public func wait() async {
        let current = now()
        let start = max(current, nextStart ?? current)
        nextStart = start.addingTimeInterval(minimumInterval)
        await sleeper(max(0, start.timeIntervalSince(current)))
    }

    public func deferUntil(seconds: TimeInterval?) {
        guard let seconds, seconds.isFinite, seconds > 0 else { return }
        let deferred = now().addingTimeInterval(seconds)
        if let nextStart {
            self.nextStart = max(nextStart, deferred)
        } else {
            nextStart = deferred
        }
    }
}

/// Adapter for OpenAI's speech endpoint and anything that speaks its contract.
///
/// `POST endpoint` with a Bearer key and `{model, input, voice, response_format: "pcm"}` — exactly
/// what `https://api.openai.com/v1/audio/speech` takes (`gpt-4o-mini-tts`, `tts-1`; voices such as
/// `alloy`); OpenAI rejects a request carrying fields it does not know, so nothing else is sent.
/// Two answers are understood, told apart by the response's content type:
///
/// - **raw PCM** (`audio/pcm`, or any non-JSON type): 16-bit little-endian mono at 24 kHz, which is
///   what OpenAI returns for `pcm`. No word timings; the Reader's highlight falls back to its
///   per-utterance estimate.
/// - **JSON** (`application/json`): `{"audio": <base64 little-endian mono Float32 PCM>,
///   "sample_rate": 24000, "word_timings": [{"start", "end", "start_utf16", "end_utf16"}]}` — the
///   shape a proxy uses to add word timings in front of a provider.
///
/// It neither guesses other media formats nor retains keys.
public final class HTTPVoiceEngine: SynthesisEngine, @unchecked Sendable {
    public let engineID = "http-voice-v2"
    /// The longest text sent in one request. Eco's 30 s router timeout was measured at about 210
    /// characters (`docs/superpowers/evidence/2026-09-11-heroku-eco-measurements.log`); anything
    /// longer is cut at clause boundaries and the pieces sent at once.
    static let maxRequestCharacters = 180

    private let configuration: HTTPVoiceConfiguration
    private let key: @Sendable () async throws -> String?
    private let session: URLSession
    /// One per endpoint, in the configuration's order: each mirror is rate-limited on its own.
    private let routes: [Route]
    private let pool: RoutePool

    private struct Route: Sendable {
        let endpoint: URL
        let limiter: RequestRateLimiter
    }

    /// The routes free of this engine's own requests. A request takes a free route and waits for
    /// one when every mirror is busy, so this engine never sends a mirror a second request while
    /// its first is in flight — a batch, a long utterance's pieces, a preview and a prime queue
    /// here rather than collide and draw the mirror's 429. The walk in `synthesizePiece` covers
    /// contention from other clients of the same mirrors. Released routes go to the back, so
    /// requests rotate through every mirror.
    actor RoutePool {
        private var free: [Int]
        private var waiters: [CheckedContinuation<Int, Never>] = []

        init(count: Int) { free = Array((0..<count).reversed()) }

        func acquire() async -> Int {
            if let index = free.popLast() { return index }
            return await withCheckedContinuation { waiters.append($0) }
        }

        func release(_ index: Int) {
            if waiters.isEmpty { free.insert(index, at: 0) } else { waiters.removeFirst().resume(returning: index) }
        }

        var waitingCount: Int { waiters.count }
    }

    /// `limiterSleeper` replaces every route's limiter sleep — a test's no-op, so pieces sent at
    /// once to one endpoint do not wait a real second apart.
    public init(configuration: HTTPVoiceConfiguration, key: @escaping @Sendable () async throws -> String?,
                session: URLSession = .shared, limiterSleeper: RequestRateLimiter.Sleeper? = nil) {
        self.configuration = configuration
        self.key = key
        self.session = session
        routes = configuration.endpoints.map { endpoint in
            let limiter = limiterSleeper.map { RequestRateLimiter(requestsPerMinute: configuration.requestRatePerMinute, sleeper: $0) }
                ?? RequestRateLimiter(requestsPerMinute: configuration.requestRatePerMinute)
            return Route(endpoint: endpoint, limiter: limiter)
        }
        pool = RoutePool(count: configuration.endpoints.count)
    }

    public func maxConcurrentRenders(for voiceID: String) -> Int { routes.count }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        try configuration.validate()
        let providerVoice = CloudVoiceID(rawValue: request.voiceID)?.voice ?? configuration.voice
        let pieces = ClauseSplitter.pieces(of: request.spoken, maxLength: Self.maxRequestCharacters)
        guard pieces.count > 1 else {
            return try await synthesizePiece(request.spoken, voice: providerVoice)
        }
        let results = try await withThrowingTaskGroup(of: (Int, SynthesisResult).self) { group in
            for (index, piece) in pieces.enumerated() {
                group.addTask { (index, try await self.synthesizePiece(piece, voice: providerVoice)) }
            }
            var ordered = [SynthesisResult?](repeating: nil, count: pieces.count)
            for try await (index, result) in group { ordered[index] = result }
            return ordered.compactMap { $0 }
        }
        // Pieces rendered apart carry no timings over the whole; the pilot server sends none anyway.
        return SynthesisResult(audio: PCMAudio(sampleRate: 24_000, samples: results.flatMap(\.audio.samples)), wordTimings: [])
    }

    /// One request, on a mirror free of this engine's other requests — waiting for one if every
    /// mirror is busy. A mirror that answers 429 anyway (another client's render) has its limiter
    /// deferred and the request walks on; each mirror is tried at most once, and only when all
    /// have refused does the request fail as rate limited.
    private func synthesizePiece(_ text: String, voice: String) async throws -> SynthesisResult {
        guard let key = try await key()?.trimmed, !key.isEmpty else { throw HTTPVoiceError.missingKey }
        let start = await pool.acquire()
        do {
            let result = try await walk(text, voice: voice, key: key, from: start)
            await pool.release(start)
            return result
        } catch {
            await pool.release(start)
            throw error
        }
    }

    private func walk(_ text: String, voice: String, key: String, from start: Int) async throws -> SynthesisResult {
        var refused: HTTPVoiceError?
        for attempt in 0 ..< routes.count {
            let route = routes[(start + attempt) % routes.count]
            await route.limiter.wait()
            do {
                return try await post(text: text, voice: voice, key: key, to: route.endpoint)
            } catch HTTPVoiceError.rateLimited(let retryAfter) {
                await route.limiter.deferUntil(seconds: retryAfter)
                refused = .rateLimited(retryAfter: retryAfter)
            }
        }
        throw refused ?? HTTPVoiceError.transport("no mirror answered")
    }

    private func post(text: String, voice: String, key: String, to endpoint: URL) async throws -> SynthesisResult {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(WireRequest(
            model: configuration.model,
            input: text,
            voice: voice,
            responseFormat: "pcm"
        ))

        do {
            var data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch {
                throw HTTPVoiceError.transport("request failed")
            }
            defer { data.removeAll(keepingCapacity: false) }

            guard let http = response as? HTTPURLResponse else {
                throw HTTPVoiceError.transport("no HTTP response")
            }
            if http.statusCode == 429 {
                throw HTTPVoiceError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
            }
            guard (200...299).contains(http.statusCode) else {
                throw HTTPVoiceError.server(status: http.statusCode, message: Self.safeServerMessage(status: http.statusCode))
            }
            guard data.count <= Self.maximumResponseBytes else { throw HTTPVoiceError.malformedResponse }

            guard Self.isJSON(http, data) else {
                // OpenAI's `pcm`: 16-bit little-endian mono at 24 kHz, no timings.
                let samples = try Self.sixteenBitSamples(data)
                return SynthesisResult(audio: PCMAudio(sampleRate: 24_000, samples: samples), wordTimings: [])
            }

            let wire: WireResponse
            do {
                wire = try JSONDecoder().decode(WireResponse.self, from: data)
            } catch {
                throw HTTPVoiceError.malformedResponse
            }
            guard wire.sampleRate == 24_000,
                  let bytes = Data(base64Encoded: wire.audio),
                  bytes.count <= Self.maximumResponseBytes,
                  bytes.count.isMultiple(of: MemoryLayout<UInt32>.size)
            else { throw HTTPVoiceError.malformedResponse }

            let samples: [Float] = stride(from: 0, to: bytes.count, by: MemoryLayout<UInt32>.size).map { offset in
                let bits: UInt32 = bytes.withUnsafeBytes { pointer in
                    pointer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                }
                return Float(bitPattern: UInt32(littleEndian: bits))
            }
            guard samples.allSatisfy(\.isFinite) else { throw HTTPVoiceError.malformedResponse }
            let duration = Double(samples.count) / 24_000
            return SynthesisResult(
                audio: PCMAudio(sampleRate: 24_000, samples: samples),
                wordTimings: try Self.timings(wire.wordTimings, text: text, duration: duration)
            )
        } catch let error as HTTPVoiceError {
            throw error
        } catch {
            throw HTTPVoiceError.transport("request failed")
        }
    }

    private static let maximumResponseBytes = 10 * 1024 * 1024

    /// A JSON answer is one the provider labels as such, or — for a proxy that forgot the header —
    /// one that starts with an object. Raw PCM never begins with `{`.
    static func isJSON(_ response: HTTPURLResponse, _ data: Data) -> Bool {
        if let type = response.mimeType?.lowercased(), type.contains("json") { return true }
        return data.first == UInt8(ascii: "{")
    }

    /// Little-endian signed 16-bit samples scaled to ±1. An odd byte count or nothing at all is
    /// not audio.
    static func sixteenBitSamples(_ data: Data) throws -> [Float] {
        guard !data.isEmpty, data.count.isMultiple(of: MemoryLayout<Int16>.size) else { throw HTTPVoiceError.malformedResponse }
        return stride(from: 0, to: data.count, by: MemoryLayout<Int16>.size).map { offset in
            let bits: Int16 = data.withUnsafeBytes { pointer in pointer.loadUnaligned(fromByteOffset: offset, as: Int16.self) }
            return Float(Int16(littleEndian: bits)) / 32768
        }
    }

    private static func safeServerMessage(status: Int) -> String {
        // Do not surface provider-controlled error bodies: a proxy can echo credentials or other
        // sensitive request material. The status still gives the user an actionable error.
        switch status {
        case 401, 403: "key rejected"
        default: "request rejected"
        }
    }

    private static func timings(_ wireTimings: [WireTiming]?, text: String, duration: TimeInterval) throws -> [WordTiming] {
        guard let wireTimings else { return [] }
        let textLength = text.utf16.count
        var previousStart: TimeInterval = -1
        var previousEnd: TimeInterval = -1
        var previousRangeEnd = 0
        return try wireTimings.map { timing in
            guard timing.start.isFinite, timing.end.isFinite,
                  timing.start >= 0, timing.end >= timing.start, timing.end <= duration,
                  timing.start >= previousStart, timing.end >= previousEnd,
                  timing.startUTF16 >= 0, timing.endUTF16 > timing.startUTF16,
                  timing.startUTF16 >= previousRangeEnd,
                  timing.endUTF16 <= textLength
            else { throw HTTPVoiceError.malformedResponse }
            previousStart = timing.start
            previousEnd = timing.end
            previousRangeEnd = timing.endUTF16
            return WordTiming(spokenRange: timing.startUTF16..<timing.endUTF16, start: timing.start, end: timing.end)
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct WireRequest: Encodable {
    var model: String
    var input: String
    var voice: String
    var responseFormat: String

    enum CodingKeys: String, CodingKey {
        case model, input, voice
        case responseFormat = "response_format"
    }
}

private struct WireResponse: Decodable {
    var audio: String
    var sampleRate: Int
    var wordTimings: [WireTiming]?

    enum CodingKeys: String, CodingKey {
        case audio
        case sampleRate = "sample_rate"
        case wordTimings = "word_timings"
    }
}

private struct WireTiming: Decodable {
    var start: TimeInterval
    var end: TimeInterval
    var startUTF16: Int
    var endUTF16: Int

    enum CodingKeys: String, CodingKey {
        case start, end
        case startUTF16 = "start_utf16"
        case endUTF16 = "end_utf16"
    }
}
