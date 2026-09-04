// App/T2SReader/System/GatedKokoroEngine.swift
#if KOKORO_ENGINE
import Foundation
import T2SAudio
import T2SCore
import T2SKokoro

/// The `kokoro:` route the router sees. Every request first awaits the availability verdict — which
/// verified the model checksums — so `KokoroEngine`, whose model loader cannot fail safely on a bad
/// file, is only ever constructed after verification and with the decision's GPU cache limit. An
/// unavailable verdict throws `KokoroRouteError.unavailable`, which the render policy surfaces as a
/// failed utterance; a document should have been routed away from Kokoro long before that (spec §6).
actor GatedKokoroEngine: SynthesisEngine {
    nonisolated let engineID = KokoroEngine.identity

    private let availability: KokoroAvailabilityModel
    /// The one engine, as a task so that concurrent first requests — live playback and Prepare —
    /// join the same construction instead of each loading 340 MB of weights.
    private var creation: Task<KokoroEngine, any Error>?

    init(availability: KokoroAvailabilityModel) {
        self.availability = availability
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        try await engine().synthesize(request)
    }

    private func engine() async throws -> KokoroEngine {
        if let creation { return try await creation.value }
        let availability = availability
        let engineID = engineID
        // Assigned before the first suspension point, so a second caller finds this task.
        let creation = Task<KokoroEngine, any Error> {
            guard case .available(let decision, let resources) = await availability.resolve() else {
                throw KokoroRouteError.unavailable(engineID: engineID)
            }
            return KokoroEngine(resources: resources, gpuCacheLimitBytes: decision.gpuCacheLimitBytes)
        }
        self.creation = creation
        return try await creation.value
    }
}
#endif
