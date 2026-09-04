// App/T2SReader/System/GatedKokoroCoreMLEngine.swift
#if KOKORO_ENGINE
import Foundation
import T2SAudio
import T2SCore
import T2SKokoro

/// The Core ML `kokoro:` route the router sees, gated on the configuration-time verdict exactly like
/// ``GatedKokoroEngine`` (spec §3, §6).
///
/// The gate is cheaper here than on the MLX route — ``KokoroCoreMLAvailabilityModel`` answered
/// synchronously at launch, so this type only reads its verdict — but it is still a gate: an
/// unavailable verdict throws `KokoroRouteError.unavailable`, which the render policy surfaces as a
/// failed utterance, and a document should have been routed away from Kokoro long before that.
///
/// The expensive part is the engine itself: eight `MLModel`s that take seconds to load and, on a
/// bundle whose stages were not precompiled, minutes to compile. So there is exactly one, built by
/// one task that every caller joins — live playback, Prepare, and the launch warm-up alike.
actor GatedKokoroCoreMLEngine: SynthesisEngine {
    nonisolated let engineID = KokoroCoreMLEngine.identity

    /// Read once, at construction, on the main actor where the model lives: the verdict is a
    /// `let` decided in the model's `init` and never changes for the life of the launch.
    private let verdict: KokoroCoreMLAvailability.Verdict
    private var creation: Task<KokoroCoreMLEngine, any Error>?

    @MainActor
    init(availability: KokoroCoreMLAvailabilityModel) {
        verdict = availability.verdict
    }

    /// Loads the stages now rather than on the first utterance. The launch warm-up calls this so the
    /// seconds are spent while the reader is still choosing a book (spec §6).
    func preload() async throws {
        _ = try await engine()
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        try await engine().synthesize(request)
    }

    private func engine() async throws -> KokoroCoreMLEngine {
        if let creation { return try await creation.value }
        let verdict = verdict
        let engineID = engineID
        // Assigned before the first suspension point, so a second caller finds this task.
        let creation = Task<KokoroCoreMLEngine, any Error> {
            guard case .available(_, let resources) = verdict else {
                throw KokoroRouteError.unavailable(engineID: engineID)
            }
            let engine = KokoroCoreMLEngine(resources: resources)
            try await engine.preload()
            return engine
        }
        self.creation = creation
        return try await creation.value
    }
}
#endif
