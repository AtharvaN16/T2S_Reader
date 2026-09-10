import Foundation
import os

/// Whether the app is frontmost — the one fact iOS's background rules turn on.
///
/// iOS kills a process that is not frontmost and holds 80% of a core for a minute
/// (`cpu_resource_fatal`; the iPhone 17 Pro's report of 2026-09-09 15:14 is exactly that, inside
/// Core ML's compute-plan compile after the phone locked). Work that cannot be paced — a first
/// warm-up's plan builds, the model installer's compiles — waits on this gate instead; work that
/// can be paced consults ``CPUBudget``, which reads it.
///
/// The app opens and closes it from `scenePhase`. A process launched for a background task never
/// opens it, so nothing heavy starts there. Waiting is cancellable: a cancelled waiter returns at
/// once, and its caller's own `Task.checkCancellation()` says what to do about it.
public final class ForegroundGate: Sendable {
    private struct State {
        var isForeground: Bool
        var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(isForeground: Bool = false) {
        state = OSAllocatedUnfairLock(initialState: State(isForeground: isForeground))
    }

    public var isForeground: Bool { state.withLock { $0.isForeground } }

    /// Opens (`true`) or closes the gate. Opening resumes everyone waiting.
    public func set(foreground: Bool) {
        let resumed: [CheckedContinuation<Void, Never>] = state.withLock { state in
            state.isForeground = foreground
            guard foreground else { return [] }
            let waiting = state.waiters.map(\.continuation)
            state.waiters.removeAll()
            return waiting
        }
        resumed.forEach { $0.resume() }
    }

    /// Returns at once while the app is frontmost, else suspends until it is — or until the caller
    /// is cancelled, in which case it returns without waiting for the foreground.
    public func waitUntilForeground() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow: Bool = state.withLock { state in
                    if state.isForeground || Task.isCancelled { return true }
                    state.waiters.append((id, continuation))
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            let cancelled: CheckedContinuation<Void, Never>? = state.withLock { state in
                guard let index = state.waiters.firstIndex(where: { $0.id == id }) else { return nil }
                return state.waiters.remove(at: index).continuation
            }
            cancelled?.resume()
        }
    }
}
