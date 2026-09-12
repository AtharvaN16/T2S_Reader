// App/T2SReader/System/GatedKokoroCoreMLEngine.swift
#if KOKORO_ENGINE
import Foundation
import T2SAudio
import T2SCore
import T2SKokoro

/// The Core ML `kokoro:` route the router sees, gated on the availability verdict exactly like
/// ``GatedKokoroEngine`` (spec §3, §6).
///
/// The gate is cheaper here than on the MLX route — ``KokoroCoreMLAvailabilityModel`` answered
/// synchronously at launch, and an install that finishes later moves its verdict — but it is still
/// a gate: an unavailable verdict throws `KokoroRouteError.unavailable`, which the render policy
/// surfaces as a failed utterance, and a document should have been routed away from Kokoro long
/// before that.
///
/// Only the *construction* of the engine is memoized here. Loading it is not: `KokoroCoreMLEngine`
/// owns its own idempotent, self-retrying ``KokoroCoreMLEngine/preload()`` — it clears its in-flight
/// compile on failure so the next render tries again — and Core ML is now what "default" resolves
/// to, so a transient failure at launch must not become a whole session of silent utterances.
actor GatedKokoroCoreMLEngine: SynthesisEngine {
    nonisolated let engineID = KokoroCoreMLEngine.identity

    /// Read when the engine is first needed, on the main actor where the model lives: the verdict is
    /// decided in the model's `init` and moves once, when an install completes.
    private let availability: KokoroCoreMLAvailabilityModel
    private let computeUnits: KokoroComputeUnits
    /// The compute units of the background set, on a phone whose main set is on the GPU; nil where
    /// the main set may render anywhere (`KokoroCoreMLEngine.Options.backgroundComputeUnits`).
    private let backgroundComputeUnits: KokoroComputeUnits?
    /// False on GPU phones: their fallback CPU plans take minutes to build and can cross the
    /// foreground boundary inside Core ML, where iOS terminates the sustained background CPU use.
    private let loadsBackgroundSet: Bool
    /// Awaited before every stage's compute-plan build: the app's foreground gate.
    private let admission: @Sendable () async -> Void
    /// Where a render is, as the same gate sees it: the engine asks before every piece.
    private let placement: @Sendable () -> KokoroCoreMLEngine.RenderPlacement
    /// The one engine. Fourteen `MLModel`s are far too expensive to hold twice, and every caller —
    /// live playback, Prepare, the launch warm-up — must reach the same instance.
    private var constructed: KokoroCoreMLEngine?

    init(availability: KokoroCoreMLAvailabilityModel, computeUnits: KokoroComputeUnits = .cpu,
         backgroundComputeUnits: KokoroComputeUnits? = nil,
         loadsBackgroundSet: Bool = true,
         admission: @escaping @Sendable () async -> Void,
         placement: @escaping @Sendable () -> KokoroCoreMLEngine.RenderPlacement = { .foreground }) {
        self.availability = availability
        self.computeUnits = computeUnits
        self.backgroundComputeUnits = backgroundComputeUnits
        self.loadsBackgroundSet = loadsBackgroundSet
        self.admission = admission
        self.placement = placement
    }

    /// Waits for the background set, where the options ask for one, and says whether the engine can
    /// render in the background now (`KokoroCoreMLEngine.awaitBackgroundSet`).
    func awaitBackgroundSet() async throws -> Bool {
        try await engine().awaitBackgroundSet()
    }

    /// Loads the stages now rather than on the first utterance. The launch warm-up calls this so the
    /// seconds are spent while the reader is still choosing a book (spec §6). Safe to call again: a
    /// loaded engine returns immediately, and a failed load is retried rather than remembered.
    func preload() async throws {
        try await engine().preload()
    }

    /// `preload`, reporting `(loaded, total)` stages as they come, for the warm-up's veil.
    func preload(onProgress: @escaping @Sendable (Int, Int) -> Void) async throws {
        let engine = try await engine()
        await engine.setLoadProgress(onProgress)
        defer { Task { await engine.setLoadProgress(nil) } }
        try await engine.preload()
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        try await engine().synthesize(request)
    }

    nonisolated func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in try await self.engine().synthesizeStreaming(request) { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Constructing the engine only stores the resource URLs the verdict vouched for, so there is
    /// nothing here that can fail transiently. The verdict is read on the main actor — one hop —
    /// and the actor's own isolation makes the construction happen once.
    private func engine() async throws -> KokoroCoreMLEngine {
        if let constructed { return constructed }
        let availability = self.availability
        let verdict = await MainActor.run { availability.verdict }
        guard case .available(_, let resources) = verdict else {
            throw KokoroRouteError.unavailable(engineID: engineID)
        }
        if let constructed { return constructed }                 // a second caller crossed the hop first
        var options = KokoroCoreMLEngine.Options.default
        options.computeUnits = computeUnits
        options.backgroundComputeUnits = backgroundComputeUnits
        options.loadsBackgroundSet = loadsBackgroundSet
        // t256 is an optional optimization, but its device specialization occupies one core for
        // 158–512 seconds and cannot be interrupted when the listener backgrounds the app.
        options.loadsLaterDurationModels = false
        let engine = KokoroCoreMLEngine(resources: resources, options: options)
        await engine.setLoadAdmission(admission)
        await engine.setRenderPlacement(placement)
        constructed = engine
        return engine
    }
}
#endif
