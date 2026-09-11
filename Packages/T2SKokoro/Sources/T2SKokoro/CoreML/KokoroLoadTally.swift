import Foundation

/// One set's stage loads, tallied for the line that says what a warm-up cost — the number a first
/// launch is watched for: how many stages, how long, how many had their compute plan built rather
/// than found in the cache, and which was slowest. A load found in the cache takes about a second
/// on the A13; a plan build takes a minute or more (59 s and 228 s on 2026-09-11), so the split is
/// at ``rebuildThresholdSeconds``.
struct KokoroLoadTally: Sendable {
    static let rebuildThresholdSeconds = 5.0

    let label: String
    let total: Int
    let startedAt: ContinuousClock.Instant
    private(set) var loaded = 0
    private(set) var rebuilt = 0
    private(set) var slowest: (name: String, seconds: Double)?

    init(label: String, total: Int, startedAt: ContinuousClock.Instant = .now) {
        self.label = label
        self.total = total
        self.startedAt = startedAt
    }

    /// Counts one stage, and returns the summary line when it was the set's last.
    mutating func record(_ name: String, seconds: Double, now: ContinuousClock.Instant = .now) -> String? {
        loaded += 1
        if seconds >= Self.rebuildThresholdSeconds { rebuilt += 1 }
        if seconds > (slowest?.seconds ?? -1) { slowest = (name, seconds) }
        guard loaded == total else { return nil }
        let wall = now - startedAt
        let wallSeconds = Double(wall.components.seconds) + Double(wall.components.attoseconds) * 1e-18
        var line = "kokoro \(label) loaded: \(total) stages in \(String(format: "%.1f", wallSeconds)) s, "
            + "\(rebuilt) rebuilt (a plan built, ≥ \(Int(Self.rebuildThresholdSeconds)) s)"
        if let slowest {
            line += ", slowest \(slowest.name) \(String(format: "%.2f", slowest.seconds)) s"
        }
        return line
    }
}
