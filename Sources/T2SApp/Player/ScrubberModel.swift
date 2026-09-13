import Foundation
import T2SCore

/// The tick scrubber (spec §2.4.5): uniform ticks, rendered ones in `ink`, unrendered in `ink3`, so
/// the render frontier (spec §3.3) is visible without a legend. A tick counts as rendered only when
/// every utterance overlapping its span has audio.
public struct ScrubberModel: Hashable, Sendable {
    public var tickCount: Int
    public var renderedTicks: [Bool]
    /// The current chapter's own frontier at the full tick count, for chapter scope (2026-09-13).
    /// The book pass cannot be reused there: chapter 2 of a 24-hour book owns about five of the 48
    /// ticks, and stretched over 360 pt five ticks are a smear rather than a frontier. Empty when
    /// there is no current chapter.
    public var chapterTicks: [Bool]
    /// Playhead position 0…1 along the total (estimated) duration.
    public var fraction: Double

    public init(tickCount: Int, renderedTicks: [Bool], chapterTicks: [Bool] = [], fraction: Double) {
        self.tickCount = tickCount
        self.renderedTicks = renderedTicks
        self.chapterTicks = chapterTicks
        self.fraction = fraction
    }

    public static func make(timeline: Timeline, timeIndex: TimeIndex, playhead: Playhead, tickCount: Int = 48) -> ScrubberModel {
        let total = timeIndex.totalDuration
        let fraction = total > 0 ? min(1, max(0, timeIndex.time(at: playhead) / total)) : 0
        let chapter = timeline.chapterIndex(forUtterance: playhead.utteranceIndex)
        return ScrubberModel(tickCount: tickCount,
                             renderedTicks: renderedTicks(timeline: timeline, timeIndex: timeIndex, tickCount: tickCount),
                             chapterTicks: chapter.map {
                                 chapterTicks(timeline: timeline, timeIndex: timeIndex, chapterIndex: $0, tickCount: tickCount)
                             } ?? [],
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

    /// One chapter's frontier, `tickCount` ticks across that chapter alone. Same rule as the book
    /// pass — a tick counts as rendered only when every utterance overlapping its span has audio —
    /// but the running start is the chapter's, so the whole bar is the chapter. A chapter that is
    /// not there, or has no utterances, reads as entirely unrendered rather than entirely ready:
    /// an empty bar is the honest answer to "how much of this is on the device".
    public static func chapterTicks(timeline: Timeline, timeIndex: TimeIndex, chapterIndex: Int,
                                    tickCount: Int = 48) -> [Bool] {
        let count = max(0, tickCount)
        guard count > 0, timeline.chapters.indices.contains(chapterIndex) else {
            return Array(repeating: false, count: count)
        }
        // The chapter's first utterance on the flat index `timeIndex` is built over, counted the
        // same way `ChapterEntry.axis` counts it rather than through `utteranceRange(ofChapter:)`,
        // which is O(chapters) per call.
        var first = 0
        for c in 0..<chapterIndex { first += timeline.chapters[c].utterances.count }
        let chapter = timeline.chapters[chapterIndex]
        let span = timeIndex.startTime(ofUtterance: first + chapter.utterances.count)
            - timeIndex.startTime(ofUtterance: first)
        guard span > 0 else { return Array(repeating: false, count: count) }

        var ticks = Array(repeating: true, count: count)
        let width = span / Double(count)
        var start: TimeInterval = 0
        for u in chapter.utterances.indices {
            let index = first + u
            let seconds = index < timeIndex.durations.count ? timeIndex.durations[index] : chapter.utterances[u].duration.seconds
            let end = start + seconds
            if chapter.utterances[u].audioRef == nil {
                let lo = min(count - 1, max(0, Int((start / width).rounded(.down))))
                let hi = min(count - 1, max(lo, Int((end / width).rounded(.up)) - 1))
                for t in lo...hi { ticks[t] = false }
            }
            start = end
        }
        return ticks
    }

    /// The frontier as contiguous runs rather than as one tick apiece, over `slice` of `ticks`
    /// (clamped) and with indices relative to that slice's start.
    ///
    /// `ThinScrubber` drew the grid as an `HStack` of one `Rectangle` per tick: 48 flexible
    /// children whose widths SwiftUI negotiated on every frame of the scope spring, while the bar
    /// containing them was itself resizing. The picture is the same drawn as merged rectangles —
    /// a realistic frontier is two or three of them — and a `Shape` has no layout children at all.
    public static func runs(of value: Bool, in ticks: [Bool], over slice: Range<Int>? = nil) -> [Range<Int>] {
        let bounds = slice ?? 0..<ticks.count
        let lo = max(0, bounds.lowerBound)
        let hi = min(ticks.count, bounds.upperBound)
        guard lo < hi else { return [] }
        var runs: [Range<Int>] = []
        var i = lo
        while i < hi {
            guard ticks[i] == value else { i += 1; continue }
            var j = i
            while j + 1 < hi, ticks[j + 1] == value { j += 1 }
            runs.append((i - lo)..<(j + 1 - lo))
            i = j + 1
        }
        return runs
    }

    /// Bookmark marks merged where they would otherwise sit on top of each other, as spans in
    /// whatever unit `positions` is in — points, when the bar places them.
    ///
    /// A 4 pt mark needs about 6 pt between centres to read as two, and on a 354 pt bar that is a
    /// 22nd of the book: over twenty-two hours, any two bookmarks made in the same sitting land on
    /// the same pixel. Merging by distance rather than dropping one keeps the information — a pair
    /// becomes a short lozenge, a densely marked stretch a longer one — and bounds the marks drawn
    /// by the width of the bar rather than by the size of the reader's library.
    ///
    /// Chained deliberately: each mark joins the run if it is within `minGap` of the one before,
    /// so a trail of close bookmarks is one span even though its ends are far apart. That is what
    /// is true of the book — there are bookmarks all through that stretch.
    public static func clusters(of positions: [Double], within minGap: Double) -> [ClosedRange<Double>] {
        let sorted = positions.sorted()
        guard let first = sorted.first else { return [] }
        var spans: [ClosedRange<Double>] = []
        var lower = first, upper = first
        for p in sorted.dropFirst() {
            if p - upper <= minGap {
                upper = p
            } else {
                spans.append(lower...upper)
                lower = p
                upper = p
            }
        }
        spans.append(lower...upper)
        return spans
    }
}
