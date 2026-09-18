import Foundation
import Testing
@testable import T2SCore

@Suite struct TimelineTests {
    let t = makeTimeline([
        [makeUtterance("a", seconds: 1), makeUtterance("b", seconds: 2)],
        [makeUtterance("c", seconds: 3, href: "ch2.xhtml"), makeUtterance("d", seconds: 4, href: "ch2.xhtml"), makeUtterance("e", seconds: 5, href: "ch2.xhtml")],
        [makeUtterance("f", seconds: 6, href: "ch3.xhtml")],
    ])

    @Test func countsAndRanges() {
        #expect(t.utteranceCount == 6)
        #expect(t.utteranceRange(ofChapter: 0) == 0..<2)
        #expect(t.utteranceRange(ofChapter: 1) == 2..<5)
        #expect(t.utteranceRange(ofChapter: 2) == 5..<6)
    }

    @Test func chapterLookup() {
        #expect(t.chapterIndex(forUtterance: 0) == 0)
        #expect(t.chapterIndex(forUtterance: 4) == 1)
        #expect(t.chapterIndex(forUtterance: 5) == 2)
        #expect(t.chapterIndex(forUtterance: 6) == nil)
    }

    @Test func subscriptGetAndSet() {
        var t = t
        #expect(t[utterance: 3].source == "d")
        t[utterance: 3].duration = .actual(4.5)
        #expect(t[utterance: 3].duration.isActual)
        #expect(t.chapters[1].utterances[1].duration.seconds == 4.5)
    }

    @Test func derivedTimes() {
        #expect(t.startTime(ofUtterance: 0) == 0)
        #expect(t.startTime(ofUtterance: 2) == 3)
        #expect(t.startTime(ofUtterance: 5) == 15)
        #expect(t.startTime(ofUtterance: 6) == 21)     // end of timeline
        #expect(t.totalDuration == 21)
        #expect(t.isFullyRendered == false)
    }

    @Test func versionsDefaultFromVersions() {
        #expect(t.schemaVersion == Versions.schema)
        #expect(t.segmenterVersion == Versions.segmenter)
        #expect(t.normalizerVersion == Versions.normalizer)
    }

    /// The flat index each chapter starts at, plus the total, kept in step with every mutation of
    /// `chapters` — the lookups below read it instead of walking the chapters.
    @Test func chapterStartsFollowTheChapters() {
        #expect(t.chapterStarts == [0, 2, 5, 6])
        var t = t
        t.chapters.append(Chapter(title: "Chapter 4", position: Position(resourceHref: "ch4.xhtml", progression: 0),
                                  utterances: [makeUtterance("g", href: "ch4.xhtml")]))
        #expect(t.chapterStarts == [0, 2, 5, 6, 7])
        t.chapters[0].utterances.removeLast()
        #expect(t.chapterStarts == [0, 1, 4, 5, 6])
        #expect(t.utteranceCount == 6)
        #expect(t.chapterIndex(forUtterance: 1) == 1)
        #expect(t[utterance: 4].source == "f")
        #expect(t.utteranceRange(ofChapter: 2) == 4..<5)
        t.chapters.removeAll()
        #expect(t.chapterStarts == [0])
        #expect(t.utteranceCount == 0)
        #expect(t.chapterIndex(forUtterance: 0) == nil)
    }

    /// An empty chapter shares the next one's start; an utterance on that index belongs to the
    /// chapter that actually holds it, and an index past the end belongs to none.
    @Test func emptyChaptersShareTheNextStart() {
        let t = makeTimeline([[makeUtterance("a")], [], [], [makeUtterance("b"), makeUtterance("c")], []])
        #expect(t.chapterStarts == [0, 1, 1, 1, 3, 3])
        #expect(t.chapterIndex(forUtterance: 0) == 0)
        #expect(t.chapterIndex(forUtterance: 1) == 3)
        #expect(t.chapterIndex(forUtterance: 2) == 3)
        #expect(t.chapterIndex(forUtterance: 3) == nil)
        #expect(t.chapterIndex(forUtterance: -1) == nil)
        #expect(t.utteranceRange(ofChapter: 1) == 1..<1)
        #expect(t.utteranceRange(ofChapter: 4) == 3..<3)
        #expect(t[utterance: 2].source == "c")
    }

    /// The table is derived, never stored: a timeline encodes as it always did, and one decoded
    /// without it answers the same lookups.
    @Test func theStartsAreNotPartOfTheEncoding() throws {
        let json = try JSONEncoder().encode(t)
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["chapterStarts"] == nil)
        let back = try JSONDecoder().decode(Timeline.self, from: json)
        #expect(back.chapterStarts == [0, 2, 5, 6])
        #expect(back == t)
    }
}
