import Foundation

/// Prefix sums over utterance durations at 1x. Build once per timeline revision; every lookup
/// is O(1) or O(log n), unlike `Timeline.startTime(ofUtterance:)` which is O(n) per call.
public struct TimeIndex: Hashable, Sendable {
    /// `starts[i]` is the start time of utterance `i`; `starts[count]` is the total duration.
    public let starts: [TimeInterval]
    /// `durations[i]` is utterance `i`'s exact duration, stored rather than derived from a
    /// subtraction of accumulated prefix sums (which can be off by a floating-point ULP or two).
    public let durations: [TimeInterval]

    public init(_ timeline: Timeline) {
        var s: [TimeInterval] = [0]
        s.reserveCapacity(timeline.utteranceCount + 1)
        var d: [TimeInterval] = []
        d.reserveCapacity(timeline.utteranceCount)
        var acc: TimeInterval = 0
        for ch in timeline.chapters {
            for i in ch.utterances.indices {
                let seconds = ch.utterances[i].duration.seconds
                acc += seconds
                s.append(acc)
                d.append(seconds)
            }
        }
        starts = s
        durations = d
    }

    public var utteranceCount: Int { starts.count - 1 }
    public var totalDuration: TimeInterval { starts[starts.count - 1] }

    public func startTime(ofUtterance i: Int) -> TimeInterval { starts[i] }
    public func duration(ofUtterance i: Int) -> TimeInterval { durations[i] }

    public func time(at ph: Playhead) -> TimeInterval {
        let c = clamp(ph)
        return utteranceCount == 0 ? 0 : starts[c.utteranceIndex] + c.offset
    }

    /// The utterance whose span contains `t`; a boundary belongs to the utterance that starts there.
    public func playhead(atTime t: TimeInterval) -> Playhead {
        guard utteranceCount > 0 else { return Playhead(utteranceIndex: 0, offset: 0) }
        if t <= 0 { return Playhead(utteranceIndex: 0, offset: 0) }
        if t >= totalDuration { return Playhead(utteranceIndex: utteranceCount - 1, offset: duration(ofUtterance: utteranceCount - 1)) }
        var lo = 0, hi = utteranceCount - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= t { lo = mid } else { hi = mid - 1 }
        }
        return Playhead(utteranceIndex: lo, offset: t - starts[lo])
    }

    public func advance(_ ph: Playhead, by seconds: TimeInterval) -> Playhead {
        playhead(atTime: time(at: ph) + seconds)
    }

    /// Keeps the index inside the timeline and the offset inside its utterance.
    public func clamp(_ ph: Playhead) -> Playhead {
        guard utteranceCount > 0 else { return Playhead(utteranceIndex: 0, offset: 0) }

        if ph.utteranceIndex >= utteranceCount {
            // Out of bounds - move to end of timeline
            return Playhead(utteranceIndex: utteranceCount - 1, offset: duration(ofUtterance: utteranceCount - 1))
        }

        let i = max(0, ph.utteranceIndex)
        return Playhead(utteranceIndex: i, offset: max(0, min(ph.offset, duration(ofUtterance: i))))
    }
}
