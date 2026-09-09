import Foundation
import T2SCore
import T2SStore

/// What a row needs to say where the listener is: remaining time, chapter n of m (spec §2.4.5).
/// Derived from the persisted `Position` through the timeline (spec §3.2), never stored.
public struct DocumentProgress: Hashable, Sendable {
    public var elapsedSeconds: TimeInterval
    public var totalSeconds: TimeInterval
    public var chapterIndex: Int?
    public var chapterCount: Int
    /// True until every utterance has an actual duration and audio (spec §3.3: totals are `~` until then).
    public var isApproximate: Bool

    public var remainingSeconds: TimeInterval { max(0, totalSeconds - elapsedSeconds) }
    public var fraction: Double { totalSeconds > 0 ? min(1, max(0, elapsedSeconds / totalSeconds)) : 0 }

    /// From a row that carries its playhead's elapsed time (Plan 16): no decode. Nil for a document
    /// never played through the coordinator, or whose position was last saved without its time.
    public static func fromSummary(_ s: DocumentSummary) -> DocumentProgress? {
        guard let elapsed = s.resumeElapsedSeconds else { return nil }
        return DocumentProgress(elapsedSeconds: min(max(0, elapsed), s.totalSeconds), totalSeconds: s.totalSeconds,
                                chapterIndex: s.resumeChapterIndex, chapterCount: s.chapterCount,
                                isApproximate: !s.isFullyRendered)
    }

    public static func compute(summary: DocumentSummary, timeline: Timeline) -> DocumentProgress {
        let index = TimeIndex(timeline)
        guard timeline.utteranceCount > 0 else {
            return DocumentProgress(elapsedSeconds: 0, totalSeconds: 0, chapterIndex: nil,
                                    chapterCount: timeline.chapters.count, isApproximate: !timeline.isFullyRendered)
        }
        let playhead = summary.document.resumePosition.map { PositionResolver.resolve($0, in: timeline) } ?? Playhead(utteranceIndex: 0)
        return DocumentProgress(elapsedSeconds: index.time(at: playhead), totalSeconds: index.totalDuration,
                                chapterIndex: timeline.chapterIndex(forUtterance: playhead.utteranceIndex),
                                chapterCount: timeline.chapters.count, isApproximate: !timeline.isFullyRendered)
    }
}
