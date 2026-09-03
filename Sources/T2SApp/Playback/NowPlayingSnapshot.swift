import Foundation

/// Pure Now Playing metadata and validation shared by the MediaPlayer boundary and tests.
public struct NowPlayingSnapshot: Hashable, Sendable {
    public var title: String
    public var author: String
    public var duration: TimeInterval
    public var elapsed: TimeInterval
    public var rate: Double
    public var isPlaying: Bool
    public var chapterIndex: Int?
    public var chapterCount: Int
    public var queueIndex: Int?
    public var queueCount: Int

    /// Zero pauses the system's elapsed-time extrapolation.
    public var playbackRate: Double { isPlaying ? rate : 0 }
    public var defaultPlaybackRate: Double { rate }
    /// MediaPlayer's chapter number is one-based while the timeline is zero-based.
    public var chapterNumber: Int? { chapterIndex.map { $0 + 1 } }

    public init(title: String, author: String, duration: TimeInterval, elapsed: TimeInterval, rate: Double,
                isPlaying: Bool, chapterIndex: Int?, chapterCount: Int, queueIndex: Int?, queueCount: Int) {
        self.title = title
        self.author = author
        self.duration = max(0, duration)
        self.elapsed = Self.clampedSeek(elapsed, duration: duration)
        self.rate = rate
        self.isPlaying = isPlaying
        self.chapterIndex = chapterIndex
        self.chapterCount = chapterCount
        self.queueIndex = queueIndex
        self.queueCount = queueCount
    }

    /// Rejects remote rates that are not explicitly advertised by the coordinator.
    public static func acceptedRate(_ value: Double, available: [Double]) -> Double? {
        available.first { abs($0 - value) < 0.001 }
    }

    public static func clampedSeek(_ value: TimeInterval, duration: TimeInterval) -> TimeInterval {
        min(max(0, value), max(0, duration))
    }
}
