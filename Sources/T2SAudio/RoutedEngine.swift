import Foundation
import T2SCore

/// Routes stable voice IDs to the built-in system engine, the on-device Kokoro engine, or the
/// currently configured BYO-key HTTP engine. The router's own engine ID is fixed; the cloud
/// configuration fingerprint and the Kokoro engine identity travel in `voiceID`, so each supplies
/// the rendering identity required by `RenderKey` (spec §5).
public actor RoutedEngine: SynthesisEngine {
    public nonisolated let engineID = "routed-v1"

    private let system: any SynthesisEngine
    /// Every linked Kokoro runtime, by its engine identity. Empty in the everyday build; a build that
    /// links both the Core ML and the MLX engine holds one entry each, because the two render
    /// different audio for the same words and a voice ID names which (spec §5).
    private let kokoro: [String: any SynthesisEngine]
    private let configuration: @Sendable () -> HTTPVoiceConfiguration?
    private let key: @Sendable () async throws -> String?
    private let session: URLSession
    private var cloudEngines: [String: HTTPVoiceEngine] = [:]

    public init(system: any SynthesisEngine,
                kokoro: [any SynthesisEngine],
                configuration: @escaping @Sendable () -> HTTPVoiceConfiguration?,
                key: @escaping @Sendable () async throws -> String?,
                session: URLSession = .shared) {
        self.system = system
        // First wins: two engines claiming one identity would be indistinguishable to a render key,
        // so the composition root's order decides rather than a dictionary literal trap.
        self.kokoro = Dictionary(kokoro.map { ($0.engineID, $0) }, uniquingKeysWith: { first, _ in first })
        self.configuration = configuration
        self.key = key
        self.session = session
    }

    /// The single-engine form the composition root used before there was more than one runtime.
    public init(system: any SynthesisEngine,
                configuration: @escaping @Sendable () -> HTTPVoiceConfiguration?,
                key: @escaping @Sendable () async throws -> String?,
                session: URLSession = .shared,
                kokoro: (any SynthesisEngine)? = nil) {
        self.init(system: system, kokoro: kokoro.map { [$0] } ?? [],
                  configuration: configuration, key: key, session: session)
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        let routed = try await engine(for: request)
        return try await routed.engine.synthesize(routed.request)
    }

    /// Streaming is routed exactly as synthesis is: the engine that owns the voice answers.
    public nonisolated func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let routed = try await self.engine(for: request)
                    for try await chunk in routed.engine.synthesizeStreaming(routed.request) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A cloud voice renders as wide as its mirror list; everything on the device renders one at
    /// a time. Reads only the configuration closure, so it needs no actor hop.
    public nonisolated func maxConcurrentRenders(for voiceID: String) -> Int {
        guard let cloudID = CloudVoiceID(rawValue: voiceID),
              let configuration = configuration(),
              configuration.fingerprint == cloudID.fingerprint
        else { return 1 }
        return max(1, configuration.endpoints.count)
    }

    /// Resolves which engine owns `request`'s voice and the request to hand it — shared by
    /// `synthesize` and `synthesizeStreaming` so the routing rules live in exactly one place.
    private func engine(for request: SynthesisRequest) async throws -> (engine: any SynthesisEngine, request: SynthesisRequest) {
        if let kokoroID = KokoroVoiceID(rawValue: request.voiceID) {
            guard let kokoro = kokoro[kokoroID.engineID] else {
                throw KokoroRouteError.unavailable(engineID: kokoroID.engineID)
            }
            // Unchanged: the engine reads its own voice out of the ID.
            return (kokoro, request)
        }

        if let cloudID = CloudVoiceID(rawValue: request.voiceID) {
            guard let configuration = configuration(), configuration.fingerprint == cloudID.fingerprint else {
                throw HTTPVoiceError.notConfigured
            }
            try configuration.validate()
            // The fingerprint ignores mirrors on purpose (cached audio survives a mirror edit), so
            // the engine, which must know every mirror, is keyed on all of them.
            let cacheKey = ([configuration.fingerprint, String(configuration.requestRatePerMinute)]
                            + configuration.endpoints.map(\.absoluteString)).joined(separator: "\u{1F}")
            let engine: HTTPVoiceEngine
            if let existing = cloudEngines[cacheKey] {
                engine = existing
            } else {
                let created = HTTPVoiceEngine(configuration: configuration, key: key, session: session)
                cloudEngines[cacheKey] = created
                engine = created
            }
            return (engine, request)
        }

        if request.voiceID.hasPrefix("system:") {
            let identifier = String(request.voiceID.dropFirst("system:".count))
            return (system, .init(spoken: request.spoken, voiceID: identifier))
        }

        // Existing documents used bare AVSpeech voice identifiers before routes existed. Preserve
        // their compatibility while all new system choices use the explicit `system:` route.
        return (system, request)
    }
}
