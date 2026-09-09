import Foundation

/// What the coordinator saves at pause, seek, every utterance boundary, and finish (spec §3.2):
/// the semantic `Position`, and beside it where that position sits in time, so a list screen can
/// show progress without decoding a timeline (Plan 16, audit #5).
public struct SavedPlayhead: Hashable, Sendable {
    public var position: Position
    /// The chapter the playhead is in; nil when the timeline is empty.
    public var chapterIndex: Int?
    /// Seconds at 1x from the start of that chapter. The store adds the earlier chapters' durations
    /// as they stand when it is read, so a later render of another chapter cannot put it out of step.
    public var secondsIntoChapter: TimeInterval

    public init(position: Position, chapterIndex: Int?, secondsIntoChapter: TimeInterval) {
        self.position = position
        self.chapterIndex = chapterIndex
        self.secondsIntoChapter = secondsIntoChapter
    }
}

/// Where resume positions go (spec §5: local is the source of truth). `T2SStore.LibraryStore` conforms.
public protocol PlayheadStore: Sendable {
    func save(_ playhead: SavedPlayhead, for documentID: UUID) async
}
