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
}
