import Foundation
import T2SCore

/// Where a document's bookmarks fall, in the two shapes the Reader draws them: as fractions along
/// the whole duration (the scrubber's dots) and grouped under their chapter (the chapter list's
/// stamps). Pure functions over a timeline, so both surfaces agree and both can be tested without
/// a player.
public enum BookmarkGrouping {
    /// 0…1 along the total duration, in the order given. An empty or zero-length timeline yields
    /// nothing rather than dividing by zero.
    public static func fractions(_ bookmarks: [Bookmark], timeline: Timeline, index: TimeIndex) -> [Double] {
        let total = index.totalDuration
        guard timeline.utteranceCount > 0, total > 0 else { return [] }
        return bookmarks.map { bookmark in
            let playhead = PositionResolver.resolve(bookmark.position, in: timeline)
            return min(1, max(0, index.time(at: playhead) / total))
        }
    }

    /// Chapter index → its bookmarks, oldest first. A chapter with none has no key at all, so a
    /// caller can ask `grouped[i] != nil` for "does this chapter have any".
    public static func byChapter(_ bookmarks: [Bookmark], timeline: Timeline, index: TimeIndex) -> [Int: [BookmarkEntry]] {
        guard timeline.utteranceCount > 0 else { return [:] }
        var grouped: [Int: [BookmarkEntry]] = [:]
        for bookmark in bookmarks {
            let playhead = PositionResolver.resolve(bookmark.position, in: timeline)
            guard let chapter = timeline.chapterIndex(forUtterance: playhead.utteranceIndex) else { continue }
            grouped[chapter, default: []].append(BookmarkListModel.displayEntry(for: bookmark, timeline: timeline, index: index))
        }
        return grouped
    }
}
