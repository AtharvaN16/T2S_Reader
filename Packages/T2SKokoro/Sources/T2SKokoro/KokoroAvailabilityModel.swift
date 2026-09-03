import Foundation
import Observation

/// One Kokoro availability probe per launch, shared by the composition root, the voice list and the
/// voice-route fallback. They all ask the same question and only the first ask does the work — which
/// matters because the answer costs a 340 MB hash.
@MainActor
@Observable
public final class KokoroAvailabilityModel {
    public enum State: Hashable, Sendable {
        case checking
        case available(KokoroRuntimeDecision)
        case unavailable(KokoroAvailability.Reason)
    }

    public private(set) var state: State = .checking

    private let probe: KokoroAvailability.Probe
    /// The one probe. Assigned before the first suspension point in ``resolve()``, so callers that
    /// arrive while it is still running join it instead of starting another.
    @ObservationIgnored private var resolution: Task<KokoroAvailability.Verdict, Never>?

    public init(probe: KokoroAvailability.Probe) {
        self.probe = probe
    }

    @discardableResult
    public func resolve() async -> KokoroAvailability.Verdict {
        let resolution = self.resolution ?? start()
        let verdict = await resolution.value
        switch verdict {
        case .available(let decision, _): state = .available(decision)
        case .unavailable(let reason): state = .unavailable(reason)
        }
        return verdict
    }

    public var isAvailable: Bool {
        if case .available = state { return true }
        return false
    }

    /// Detached on purpose: the probe hashes hundreds of megabytes, and it must not do that on the
    /// main actor however it was called.
    private func start() -> Task<KokoroAvailability.Verdict, Never> {
        let probe = probe
        let task = Task.detached { await KokoroAvailability.check(probe) }
        resolution = task
        return task
    }
}
