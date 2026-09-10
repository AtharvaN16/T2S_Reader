import Foundation
import os

/// The process's CPU time held under iOS's background limit.
///
/// A process that is not frontmost and uses more than 80% of a core over 60 seconds is killed
/// (`cpu_resource_fatal`). Core ML renders are the only thing in this app that can get near it —
/// Prepare in the background, play-ahead at a high rate on a slow phone — so the scheduler asks
/// here before each synthesis while the app is in the background, and waits until the trailing
/// window has room. In the foreground there is no limit and nothing waits.
///
/// The window is measured from the process's own CPU clock, sampled on every call. Between two
/// samples the split is unknown, so the CPU since the newest sample *older than the window* is
/// charged in full: after a long burst the first background render may wait up to a whole window,
/// and never proceeds early. The default budget is 60% of the window, well under the fatal 80%,
/// because a render's own cost is only estimated from the last one.
public final class CPUBudget: Sendable {
    public typealias Clock = @Sendable () -> TimeInterval
    public typealias Sleeper = @Sendable (TimeInterval) async -> Void

    private struct Sample { var wall: TimeInterval; var cpu: TimeInterval }

    private let gate: ForegroundGate
    public let windowSeconds: TimeInterval
    public let budgetSeconds: TimeInterval
    private let clock: Clock
    private let cpuTime: Clock
    private let sleeper: Sleeper
    private let samples: OSAllocatedUnfairLock<[Sample]>
    private static let log = Logger(subsystem: "com.t2s.reader", category: "render.pacing")

    public init(gate: ForegroundGate, windowSeconds: TimeInterval = 60, budgetSeconds: TimeInterval = 36,
                clock: @escaping Clock = { ProcessInfo.processInfo.systemUptime },
                cpuTime: @escaping Clock = CPUBudget.processCPUSeconds,
                sleeper: @escaping Sleeper = { seconds in try? await Task.sleep(for: .seconds(seconds)) }) {
        self.gate = gate
        self.windowSeconds = windowSeconds
        self.budgetSeconds = budgetSeconds
        self.clock = clock
        self.cpuTime = cpuTime
        self.sleeper = sleeper
        samples = OSAllocatedUnfairLock(initialState: [Sample(wall: clock(), cpu: cpuTime())])
    }

    /// The process's user + system CPU time, in seconds, since it launched.
    public static let processCPUSeconds: Clock = {
        Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)) / 1e9
    }

    /// CPU seconds charged to the trailing window as of now: everything since the newest sample
    /// that is at least a window old (or since the oldest sample there is). Records a sample.
    public func usedInWindow() -> TimeInterval {
        let now = clock(), cpu = cpuTime()
        return samples.withLock { samples in
            samples.append(Sample(wall: now, cpu: cpu))
            let horizon = now - windowSeconds
            // Keep one sample at or before the horizon so the window always has a floor.
            if let keepFrom = samples.lastIndex(where: { $0.wall <= horizon }), keepFrom > 0 {
                samples.removeFirst(keepFrom)
            }
            let floor = samples.first(where: { $0.wall <= horizon })?.cpu ?? samples[0].cpu
            return max(0, cpu - floor)
        }
    }

    /// Waits, while the app is not frontmost, until `estimatedSeconds` more CPU fits in the window.
    /// Returns the seconds waited, for the caller's log line. Returns immediately in the foreground
    /// and when the caller is cancelled.
    @discardableResult
    public func waitForHeadroom(estimatedSeconds: TimeInterval) async -> TimeInterval {
        var waited: TimeInterval = 0
        var announced = false
        while !gate.isForeground, !Task.isCancelled {
            let used = usedInWindow()
            let excess = used + max(0, estimatedSeconds) - budgetSeconds
            if excess <= 0 { break }
            if !announced {
                announced = true
                Self.log.notice("render paced in the background: \(used, format: .fixed(precision: 1), privacy: .public) s of CPU in the last \(Int(self.windowSeconds), privacy: .public) s, budget \(Int(self.budgetSeconds), privacy: .public) s")
            }
            // Old CPU ages out of the window at one second per second; sleep for the excess, in
            // slices, so a return to the foreground is noticed within a few seconds.
            let slice = min(5, max(1, excess))
            await sleeper(slice)
            waited += slice
        }
        return waited
    }
}
