import Foundation

/// Phase-1 estimate (spec §3.3): ~180 words per minute ≈ 15 UTF-16 units per second.
public enum DurationEstimator {
    public static let charsPerSecond: Double = 15
    public static let floorSeconds: TimeInterval = 0.5

    public static func estimate(spoken: String) -> TimeInterval {
        max(floorSeconds, Double(spoken.utf16.count) / charsPerSecond)
    }
}
