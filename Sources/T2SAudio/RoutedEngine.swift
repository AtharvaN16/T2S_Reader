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
        if let kokoroID = KokoroVoiceID(rawValue: request.voiceID) {
            guard let kokoro = kokoro[kokoroID.engineID] else {
                throw KokoroRouteError.unavailable(engineID: kokoroID.engineID)
            }
            // Unchanged: the engine reads its own voice out of the ID.
            return try await kokoro.synthesize(request)
        }

        if let cloudID = CloudVoiceID(rawValue: request.voiceID) {
            guard let configuration = configuration(), configuration.fingerprint == cloudID.fingerprint else {
                throw HTTPVoiceError.notConfigured
            }
            try configuration.validate()
            let cacheKey = "\(configuration.fingerprint)\u{1F}\(configuration.requestRatePerMinute)"
            let engine: HTTPVoiceEngine
            if let existing = cloudEngines[cacheKey] {
                engine = existing
            } else {
                let created = HTTPVoiceEngine(configuration: configuration, key: key, session: session)
                cloudEngines[cacheKey] = created
                engine = created
            }
            return try await engine.synthesize(request)
        }

        if request.voiceID.hasPrefix("system:") {
            let identifier = String(request.voiceID.dropFirst("system:".count))
            return try await system.synthesize(.init(spoken: request.spoken, voiceID: identifier))
        }

        // Existing documents used bare AVSpeech voice identifiers before routes existed. Preserve
        // their compatibility while all new system choices use the explicit `system:` route.
        return try await system.synthesize(request)
    }
}
