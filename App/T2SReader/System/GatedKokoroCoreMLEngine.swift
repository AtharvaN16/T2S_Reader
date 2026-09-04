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
/// Only the *construction* of the engine is memoized here. Loading it is not: `KokoroCoreMLEngine`
/// owns its own idempotent, self-retrying ``KokoroCoreMLEngine/preload()`` — it clears its in-flight
/// compile on failure so the next render tries again — and Core ML is now what "default" resolves
/// to, so a transient failure at launch must not become a whole session of silent utterances.
actor GatedKokoroCoreMLEngine: SynthesisEngine {
    nonisolated let engineID = KokoroCoreMLEngine.identity

    /// Read once, at construction, on the main actor where the model lives: the verdict is a
    /// `let` decided in the model's `init` and never changes for the life of the launch.
    private let verdict: KokoroCoreMLAvailability.Verdict
    /// The one engine. Eight `MLModel`s are far too expensive to hold twice, and every caller —
    /// live playback, Prepare, the launch warm-up — must reach the same instance.
    private var constructed: KokoroCoreMLEngine?

    @MainActor
    init(availability: KokoroCoreMLAvailabilityModel) {
        verdict = availability.verdict
    }

    /// Loads the stages now rather than on the first utterance. The launch warm-up calls this so the
    /// seconds are spent while the reader is still choosing a book (spec §6). Safe to call again: a
    /// loaded engine returns immediately, and a failed load is retried rather than remembered.
    func preload() async throws {
        try await engine().preload()
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        try await engine().synthesize(request)
    }

    /// Constructing the engine only stores the resource URLs the verdict already vouched for, so
    /// there is nothing here that can fail transiently and nothing that suspends — which is why this
    /// needs no shared `Task`: the actor's own isolation is enough to make it happen once.
    private func engine() throws -> KokoroCoreMLEngine {
        if let constructed { return constructed }
        guard case .available(_, let resources) = verdict else {
            throw KokoroRouteError.unavailable(engineID: engineID)
        }
        let engine = KokoroCoreMLEngine(resources: resources)
        constructed = engine
        return engine
    }
}
#endif
