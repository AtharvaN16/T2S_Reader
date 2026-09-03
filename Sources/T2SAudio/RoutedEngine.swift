import Foundation
import T2SCore

/// Routes stable voice IDs to the built-in system engine, the on-device Kokoro engine, or the
/// currently configured BYO-key HTTP engine. The router's own engine ID is fixed; the cloud
/// configuration fingerprint and the Kokoro engine identity travel in `voiceID`, so each supplies
/// the rendering identity required by `RenderKey` (spec §5).
public actor RoutedEngine: SynthesisEngine {
    public nonisolated let engineID = "routed-v1"

    private let system: any SynthesisEngine
    /// Absent in the everyday build, which does not link MLX at all.
    private let kokoro: (any SynthesisEngine)?
    private let configuration: @Sendable () -> HTTPVoiceConfiguration?
    private let key: @Sendable () async throws -> String?
    private let session: URLSession
    private var cloudEngines: [String: HTTPVoiceEngine] = [:]

    public init(system: any SynthesisEngine,
                configuration: @escaping @Sendable () -> HTTPVoiceConfiguration?,
                key: @escaping @Sendable () async throws -> String?,
                session: URLSession = .shared,
                kokoro: (any SynthesisEngine)? = nil) {
        self.system = system
        self.configuration = configuration
        self.key = key
        self.session = session
        self.kokoro = kokoro
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        if let kokoroID = KokoroVoiceID(rawValue: request.voiceID) {
            guard let kokoro, kokoro.engineID == kokoroID.engineID else {
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
