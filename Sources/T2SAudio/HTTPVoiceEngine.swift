import CryptoKit
import Foundation
import T2SCore

/// Non-secret configuration for the generic, OpenAI-compatible cloud voice contract. The endpoint
/// is deliberately user supplied: T2S does not run a proxy or provider account (spec §1.1).
public struct HTTPVoiceConfiguration: Hashable, Sendable {
    public static let formatVersion = "pcm-f32le-word-v1"

    public let endpoint: URL
    public let model: String
    public let voice: String
    public let requestRatePerMinute: Int

    public init(endpoint: URL, model: String, voice: String, requestRatePerMinute: Int) {
        self.endpoint = endpoint
        self.model = model.trimmed
        self.voice = voice.trimmed
        self.requestRatePerMinute = requestRatePerMinute
    }

    /// A non-secret identity for rendered audio. Rate limiting is intentionally excluded: changing
    /// it does not change a provider's PCM output, while endpoint/model/voice/format do.
    public var fingerprint: String {
        let material = [Self.formatVersion, canonicalEndpoint, model.trimmed, voice.trimmed].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func validate() throws {
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              !model.isEmpty,
              !voice.isEmpty,
              (1...120).contains(requestRatePerMinute)
        else { throw HTTPVoiceError.invalidConfiguration }
    }

    private var canonicalEndpoint: String {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return endpoint.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.string ?? endpoint.absoluteString
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

/// Generic adapter for a deliberately narrow, OpenAI-compatible PCM-over-JSON contract:
///
/// `POST endpoint` with a Bearer key and `{model,input,voice,response_format:"pcm_f32le",
/// sample_rate:24000,timestamps:"word"}`, returning base64 little-endian mono Float32 PCM plus
/// optional UTF-16 word timings. It neither guesses provider media formats nor retains keys.
public final class HTTPVoiceEngine: SynthesisEngine, @unchecked Sendable {
    public let engineID = "http-voice-v1"

    private let configuration: HTTPVoiceConfiguration
    private let key: @Sendable () async throws -> String?
    private let session: URLSession
    private let limiter: RequestRateLimiter

    public init(configuration: HTTPVoiceConfiguration, key: @escaping @Sendable () async throws -> String?,
                session: URLSession = .shared, limiter: RequestRateLimiter? = nil) {
        self.configuration = configuration
        self.key = key
        self.session = session
        self.limiter = limiter ?? RequestRateLimiter(requestsPerMinute: configuration.requestRatePerMinute)
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        try configuration.validate()
        await limiter.wait()
        guard let key = try await key()?.trimmed, !key.isEmpty else { throw HTTPVoiceError.missingKey }

        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let providerVoice = CloudVoiceID(rawValue: request.voiceID)?.voice ?? configuration.voice
        urlRequest.httpBody = try JSONEncoder().encode(WireRequest(
            model: configuration.model,
            input: request.spoken,
            voice: providerVoice,
            responseFormat: "pcm_f32le",
            sampleRate: 24_000,
            timestamps: "word"
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
                let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                await limiter.deferUntil(seconds: seconds)
                throw HTTPVoiceError.rateLimited(retryAfter: seconds)
            }
            guard (200...299).contains(http.statusCode) else {
                throw HTTPVoiceError.server(status: http.statusCode, message: Self.safeServerMessage(status: http.statusCode))
            }
            guard data.count <= Self.maximumResponseBytes else { throw HTTPVoiceError.malformedResponse }

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
                wordTimings: try Self.timings(wire.wordTimings, text: request.spoken, duration: duration)
            )
        } catch let error as HTTPVoiceError {
            throw error
        } catch {
            throw HTTPVoiceError.transport("request failed")
        }
    }

    private static let maximumResponseBytes = 10 * 1024 * 1024

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
    var sampleRate: Int
    var timestamps: String

    enum CodingKeys: String, CodingKey {
        case model, input, voice, timestamps
        case responseFormat = "response_format"
        case sampleRate = "sample_rate"
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
