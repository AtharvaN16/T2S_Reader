import Foundation
import Testing
import T2SCore
@testable import T2SApp

@Suite struct BookmarkGroupingTests {
    /// Three chapters of one second each; a bookmark on the first utterance of chapters 1 and 3.
    private func fixture() -> (Timeline, TimeIndex, [Bookmark]) {
        let timeline = makeTimeline([
            [makeUtterance("One.")],
            [makeUtterance("Two.", href: "ch2.xhtml")],
            [makeUtterance("Three.", href: "ch3.xhtml")],
        ])
        let index = TimeIndex(timeline)
        let doc = UUID()
        let bookmarks = [0, 2].map { i in
            Bookmark(documentID: doc,
                     position: PositionResolver.position(for: Playhead(utteranceIndex: i), in: timeline),
                     passageText: nil, createdAt: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        return (timeline, index, bookmarks)
    }

    @Test func fractionsSitWhereTheBookmarksAreAlongTheWholeDuration() {
        let (timeline, index, bookmarks) = fixture()
        let fractions = BookmarkGrouping.fractions(bookmarks, timeline: timeline, index: index)
        #expect(fractions.count == 2)
        #expect(abs(fractions[0] - 0.0) < 0.0001)
        #expect(abs(fractions[1] - (2.0 / 3.0)) < 0.0001)
    }

    @Test func entriesGroupUnderTheChapterTheyFallIn() {
        let (timeline, index, bookmarks) = fixture()
        let grouped = BookmarkGrouping.byChapter(bookmarks, timeline: timeline, index: index)
        #expect(Set(grouped.keys) == [0, 2])
        #expect(grouped[0]?.count == 1)
        #expect(grouped[2]?.count == 1)
        #expect(grouped[1] == nil)
    }

    @Test func anEmptyTimelineYieldsNothingRatherThanCrashing() {
        let timeline = makeTimeline([])
        let index = TimeIndex(timeline)
        #expect(BookmarkGrouping.fractions([], timeline: timeline, index: index).isEmpty)
        #expect(BookmarkGrouping.byChapter([], timeline: timeline, index: index).isEmpty)
    }
}
