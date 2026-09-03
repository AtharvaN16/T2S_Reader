/// One rendering lease shared by playback and Prepare. Ownership changes only between complete
/// utterances, so an in-flight render is always safe to persist atomically.
public actor RenderArbiter {
    private var held = false
    private var waiters: [RenderTier: [CheckedContinuation<Void, Never>]] = [:]

    public init() {}

    /// Waits for the next lease. Lower `RenderTier` raw values always win the next boundary.
    public func acquire(_ tier: RenderTier) async {
        if !held {
            held = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters[tier, default: []].append(continuation)
        }
    }

    /// Transfers ownership to one waiter, or makes the lease available when there are none.
    public func release() {
        for tier in [RenderTier.playAhead, .prime, .prepare, .manual] {
            guard var queue = waiters[tier], !queue.isEmpty else { continue }
            let next = queue.removeFirst()
            waiters[tier] = queue
            next.resume()
            return
        }
        held = false
    }

    /// Internal observability for deterministic arbitration tests.
    func waitingCount() -> Int {
        waiters.values.reduce(0) { $0 + $1.count }
    }
}
