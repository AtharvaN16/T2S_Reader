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
        guard tickCount > 0, total > 0, timeline.utteranceCount > 0 else {
            return ScrubberModel(tickCount: tickCount, renderedTicks: Array(repeating: false, count: max(0, tickCount)), fraction: 0)
        }
        var rendered: [Bool] = []
        rendered.reserveCapacity(tickCount)
        for i in 0..<tickCount {
            let start = total * Double(i) / Double(tickCount)
            let end = total * Double(i + 1) / Double(tickCount)
            let first = timeIndex.playhead(atTime: start).utteranceIndex
            // The utterance containing `end` (exclusive): step back from the boundary by a hair.
            let last = timeIndex.playhead(atTime: max(start, end - 1e-9)).utteranceIndex
            var ok = true
            for u in first...max(first, last) where timeline[utterance: u].audioRef == nil { ok = false; break }
            rendered.append(ok)
        }
        let fraction = min(1, max(0, timeIndex.time(at: playhead) / total))
        return ScrubberModel(tickCount: tickCount, renderedTicks: rendered, fraction: fraction)
    }
}
