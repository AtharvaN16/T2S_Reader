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
