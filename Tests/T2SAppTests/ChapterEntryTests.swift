import Foundation
import Testing
import T2SCore
@testable import T2SApp

@Suite struct ChapterEntryTests {
    @Test func entriesCarryStartsDurationsAndProgress() {
        func u(_ text: String, _ seconds: TimeInterval, href: String) -> Utterance {
            let n = text.utf16.count
            return Utterance(position: Position(resourceHref: href, progression: 0, charOffset: 0), source: text, spoken: text,
                             spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], duration: .estimated(seconds))
        }
        let timeline = Timeline(chapters: [
            Chapter(title: "One", position: Position(resourceHref: "a", progression: 0), utterances: [u("A.", 10, href: "a"), u("B.", 10, href: "a")]),
            Chapter(title: "Two", position: Position(resourceHref: "b", progression: 0), utterances: [u("C.", 20, href: "b")]),
            Chapter(title: "Empty", position: Position(resourceHref: "c", progression: 0), utterances: []),
        ])
        let entries = ChapterEntry.entries(timeline: timeline, timeIndex: TimeIndex(timeline), elapsed: 25)
        #expect(entries.map(\.title) == ["One", "Two", "Empty"])
        #expect(entries.map(\.startSeconds) == [0, 20, 40])
        #expect(entries.map(\.durationSeconds) == [20, 20, 0])
        #expect(entries.map(\.fraction) == [1, 0.25, 0])
        #expect(ChapterEntry.entries(timeline: Timeline(chapters: []), timeIndex: TimeIndex(Timeline(chapters: [])), elapsed: 0).isEmpty)
    }
}

/// The chapter-scoped clocks under the scrubber (2026-09-13): with the bar zoomed to one chapter
/// the times read that chapter, not the book. Both come off `fraction`, which is already clamped,
/// so a playhead outside the chapter reads 0 or the whole chapter rather than a negative clock.
@Suite struct ChapterClockTests {
    private func entry(start: TimeInterval, duration: TimeInterval, elapsed: TimeInterval) -> ChapterEntry {
        ChapterEntry(index: 0, title: "One", startSeconds: start, durationSeconds: duration,
                     fraction: ChapterEntry.fraction(of: elapsed, in: ChapterSpan(title: "One", start: start, duration: duration)))
    }

    @Test func clocksMeasureTheChapterNotTheBook() {
        let e = entry(start: 3600, duration: 9000, elapsed: 9820)             // 2:43:40 into the book
        #expect(e.playedSeconds == 6220)                                      // 1:43:40 into the chapter
        #expect(e.remainingSeconds == 2780)                                   // 46:20 left of it
        #expect(e.playedSeconds + e.remainingSeconds == e.durationSeconds)
    }

    @Test func aPlayheadBeforeOrAfterTheChapterDoesNotGoNegative() {
        #expect(entry(start: 3600, duration: 9000, elapsed: 100).playedSeconds == 0)
        #expect(entry(start: 3600, duration: 9000, elapsed: 100).remainingSeconds == 9000)
        #expect(entry(start: 3600, duration: 9000, elapsed: 99_999).playedSeconds == 9000)
        #expect(entry(start: 3600, duration: 9000, elapsed: 99_999).remainingSeconds == 0)
    }

    @Test func anEmptyChapterReadsZeroBothWays() {
        let e = entry(start: 40, duration: 0, elapsed: 40)
        #expect(e.playedSeconds == 0)
        #expect(e.remainingSeconds == 0)
    }
}
