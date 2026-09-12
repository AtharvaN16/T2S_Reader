import Foundation
import Testing
import T2SCore
@testable import T2SApp

@Suite struct ChapterAudioStatusTests {
    /// `RawPCMCodec` writes an 8-byte header and four bytes a sample, so a clip's size on disk is
    /// known here and the per-chapter totals can be asserted rather than merely compared.
    private func clip(samples: Int) -> (audio: PCMAudio, bytes: Int) {
        (PCMAudio(samples: Array(repeating: 0.5, count: samples)), 8 + samples * 4)
    }

    private func store() -> InMemoryAudioStore {
        InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 1_000_000)
    }

    /// The whole of the model: a chapter counts the utterances the store holds and the bytes they
    /// occupy, and stops at its own boundary — a neighbour's audio is never in its total.
    @Test func eachChapterCountsItsOwnRenderedUtterancesAndTheirBytes() async throws {
        let audio = store()
        var timeline = makeTimeline([
            [makeUtterance("one"), makeUtterance("two")],        // both rendered
            [makeUtterance("three"), makeUtterance("four")],     // half rendered
            [makeUtterance("five")],                             // none
        ])
        let first = clip(samples: 10)
        let second = clip(samples: 20)
        let third = clip(samples: 30)
        for (index, written) in [(0, first), (1, second), (2, third)] {
            let key = RenderKey(rawValue: "key-\(index)")
            try await audio.write(written.audio, for: key)
            timeline[utterance: index].audioRef = key.rawValue
        }

        let status = await BookAudioStatus.read(timeline: timeline, audioStore: audio)

        #expect(status.chapters.map(\.rendered) == [2, 1, 0])
        #expect(status.chapters.map(\.utteranceCount) == [2, 2, 1])
        #expect(status.chapters.map(\.bytes) == [first.bytes + second.bytes, third.bytes, 0])
        #expect(status.chapters.map(\.isFullyRendered) == [true, false, false])
        #expect(status.chapters.map(\.isPartlyRendered) == [false, true, false])
        #expect(status.chapters.map(\.chapterIndex) == [0, 1, 2])
        #expect(status.chapters.map(\.title) == ["Chapter 1", "Chapter 2", "Chapter 3"])
        #expect(status.readyChapters == 1)
        let stored = await audio.stats().bytes
        #expect(status.bytes == stored)
        #expect(status.chapter(1)?.fraction == 0.5)
    }

    /// Rendered audio is cache: the LRU can drop a clip and leave its `audioRef` behind. The row
    /// must then read as unrendered — a tick and a trash over audio that is no longer there is the
    /// one thing this screen exists to stop saying.
    @Test func aReferenceWhoseClipTheCacheDroppedCountsForNothing() async throws {
        let audio = store()
        var timeline = makeTimeline([[makeUtterance("one"), makeUtterance("two")]])
        let key = RenderKey(rawValue: "kept")
        let dropped = RenderKey(rawValue: "dropped")
        try await audio.write(clip(samples: 10).audio, for: key)
        try await audio.write(clip(samples: 10).audio, for: dropped)
        timeline[utterance: 0].audioRef = key.rawValue
        timeline[utterance: 1].audioRef = dropped.rawValue
        await audio.remove(dropped)

        let status = await BookAudioStatus.read(timeline: timeline, audioStore: audio)

        #expect(status.chapters[0].rendered == 1)
        #expect(status.chapters[0].bytes == clip(samples: 10).bytes)
        #expect(status.chapters[0].isFullyRendered == false)
        #expect(status.readyChapters == 0)
    }

    /// A book with nothing on the device has no size and no chapters to evict, so the summary says
    /// so plainly and "Evict all" has nothing to offer.
    @Test func anUnrenderedBookHasNoSizeAndNothingToEvict() async {
        let audio = store()
        let timeline = makeTimeline([[makeUtterance("one")], [makeUtterance("two")]])

        let status = await BookAudioStatus.read(timeline: timeline, audioStore: audio)

        #expect(status.bytes == 0)
        #expect(!status.hasAudio)
        #expect(status.summary == "Nothing rendered yet")
        #expect(status.chapters.allSatisfy { $0.sizeText == nil })
    }

    /// The line above the list, in its three states. "Partly rendered" rather than "0 chapters
    /// ready": the fill tier's window leaves real audio on the device, and a line that reads as
    /// "nothing here" over it would make Evict all look like it does nothing.
    @Test func theSummaryLineCountsWholeChaptersAndFallsBackToTheSize() {
        func summary(_ chapters: [ChapterAudioStatus]) -> String { BookAudioStatus(chapters: chapters).summary }
        let ready = ChapterAudioStatus(chapterIndex: 0, title: "One", utteranceCount: 2, rendered: 2, bytes: 2_000_000)
        let alsoReady = ChapterAudioStatus(chapterIndex: 1, title: "Two", utteranceCount: 2, rendered: 2, bytes: 2_000_000)
        let partial = ChapterAudioStatus(chapterIndex: 2, title: "Three", utteranceCount: 4, rendered: 1, bytes: 500_000)

        #expect(summary([ready]) == "1 chapter ready · \(BookAudioStatus.sizeText(2_000_000))")
        #expect(summary([ready, alsoReady]) == "2 chapters ready · \(BookAudioStatus.sizeText(4_000_000))")
        #expect(summary([partial]) == "Partly rendered · \(BookAudioStatus.sizeText(500_000))")
        #expect(summary([ready, partial]) == "1 chapter ready · \(BookAudioStatus.sizeText(2_500_000))")
    }

    /// An empty chapter is not "ready". There is no audio in it to play, and a tick and a trash on
    /// a row with nothing behind either is a lie the row cannot take back.
    @Test func anEmptyChapterIsNeverReady() async {
        let audio = store()
        let timeline = Timeline(chapters: [Chapter(title: "Front matter",
                                                   position: Position(resourceHref: "ch1.xhtml", progression: 0),
                                                   utterances: [])])

        let status = await BookAudioStatus.read(timeline: timeline, audioStore: audio)

        #expect(status.chapters[0].isFullyRendered == false)
        #expect(status.chapters[0].fraction == 0)
        #expect(status.readyChapters == 0)
    }
}
