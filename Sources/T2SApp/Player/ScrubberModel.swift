import Foundation
import T2SCore

/// The tick scrubber (spec §2.4.5): uniform ticks, rendered ones in `ink`, unrendered in `ink3`, so
/// the render frontier (spec §3.3) is visible without a legend. A tick counts as rendered only when
/// every utterance overlapping its span has audio.
public struct ScrubberModel: Hashable, Sendable {
    public var tickCount: Int
    public var renderedTicks: [Bool]
    /// Playhead position 0…1 along the total (estimated) duration.
    public var fraction: Double

    public init(tickCount: Int, renderedTicks: [Bool], fraction: Double) {
        self.tickCount = tickCount
        self.renderedTicks = renderedTicks
        self.fraction = fraction
    }

    public static func make(timeline: Timeline, timeIndex: TimeIndex, playhead: Playhead, tickCount: Int = 48) -> ScrubberModel {
        let total = timeIndex.totalDuration
        let fraction = total > 0 ? min(1, max(0, timeIndex.time(at: playhead) / total)) : 0
        return ScrubberModel(tickCount: tickCount,
                             renderedTicks: renderedTicks(timeline: timeline, timeIndex: timeIndex, tickCount: tickCount),
                             fraction: fraction)
    }

    /// One flat pass over the chapters in order, with a running start time built from the same
    /// per-utterance durations `TimeIndex` uses. Deliberately never touches `timeline[utterance:]`
    /// or `chapterIndex(forUtterance:)`: both are O(chapters) *and* copy the utterance by value, so
    /// a per-tick lookup costs O(utterances × chapters) with a struct copy each — on the player
    /// sheet, whose body runs at 10 Hz while playing, that is the whole book ten times a second.
    /// An utterance with no `audioRef` marks every tick its `[start, end)` overlaps unrendered.
    public static func renderedTicks(timeline: Timeline, timeIndex: TimeIndex, tickCount: Int = 48) -> [Bool] {
        let count = max(0, tickCount)
        let total = timeIndex.totalDuration
        guard count > 0, total > 0 else { return Array(repeating: false, count: count) }
        var ticks = Array(repeating: true, count: count)
        let width = total / Double(count)
        var start: TimeInterval = 0
        var index = 0
        for chapter in timeline.chapters {
            for u in chapter.utterances.indices {
                let seconds = index < timeIndex.durations.count ? timeIndex.durations[index] : chapter.utterances[u].duration.seconds
                let end = start + seconds
                if chapter.utterances[u].audioRef == nil {
                    let first = min(count - 1, max(0, Int((start / width).rounded(.down))))
                    let last = min(count - 1, max(first, Int((end / width).rounded(.up)) - 1))
                    for t in first...last { ticks[t] = false }
                }
                start = end
                index += 1
            }
        }
        return ticks
    }
}
