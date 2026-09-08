import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SLibrary
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct ReaderModelTests {
    func utterance(_ text: String, href: String, offset: Int, progression: Double = 0) -> Utterance {
        let n = text.utf16.count
        return Utterance(position: Position(resourceHref: href, progression: progression, charOffset: offset), source: text, spoken: text,
                         spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], duration: .estimated(1))
    }

    var epubTimeline: Timeline {
        Timeline(chapters: [Chapter(title: "One", position: Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0), utterances: [
            utterance("First sentence.", href: "OEBPS/ch1.xhtml", offset: 0),
            utterance("Second sentence here.", href: "OEBPS/ch1.xhtml", offset: 16),
            utterance("Another block.", href: "OEBPS/ch1.xhtml", offset: 38),
        ])])
    }

    // MARK: Word-precise seeks inside a packed utterance (Plan 9 Task 2)

    /// "First sentence. Second sentence here." as one utterance, with a timing per word.
    var packedTimeline: Timeline {
        let text = "First sentence. Second sentence here."
        var u = utterance(text, href: "OEBPS/ch1.xhtml", offset: 0)
        var timings: [WordTiming] = []
        var start = 0.0
        var cursor = 0
        for word in text.split(separator: " ") {
            let range = cursor ..< cursor + word.utf16.count
            timings.append(WordTiming(spokenRange: range, start: start, end: start + 0.4))
            start += 0.5
            cursor = range.upperBound + 1
        }
        u.wordTimings = timings
        return Timeline(chapters: [Chapter(title: "One", position: Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0), utterances: [u])])
    }

    // MARK: Seeks by utterance (Plan 10: the native reader knows the utterance it drew)

    @Test func anOffsetInTheSecondSentenceSeeksToThatWordsStart() {
        let t = packedTimeline   // "First sentence. Second sentence here.", one timing per word, 0.5 s apart
        // "Second" is the third word (source offset 16): starts at 1.0 s; "here." is the fifth: 2.0 s.
        #expect(ReaderModel.playhead(utteranceIndex: 0, sourceOffset: 18, in: t) == Playhead(utteranceIndex: 0, offset: 1.0))
        #expect(ReaderModel.playhead(utteranceIndex: 0, sourceOffset: 34, in: t) == Playhead(utteranceIndex: 0, offset: 2.0))
        #expect(ReaderModel.playhead(utteranceIndex: 0, sourceOffset: 2, in: t) == Playhead(utteranceIndex: 0, offset: 0))
    }

    @Test func offsetsAreClampedAndTimingsOptional() {
        let t = epubTimeline   // no word timings → utterance start
        #expect(ReaderModel.playhead(utteranceIndex: 1, sourceOffset: 5, in: t) == Playhead(utteranceIndex: 1))
        #expect(ReaderModel.playhead(utteranceIndex: 1, sourceOffset: 999, in: t) == Playhead(utteranceIndex: 1))
        #expect(ReaderModel.playhead(utteranceIndex: 3, sourceOffset: 0, in: t) == nil)
        #expect(ReaderModel.playhead(utteranceIndex: -1, sourceOffset: 0, in: t) == nil)
    }

    @Test func seekingByUtteranceResumesFollowing() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        let reader = ReaderModel(player: player)
        #expect(reader.chapterTitle == "Chapter 1")
        reader.suspendFollowing()
        #expect(await reader.seek(toUtterance: 2, sourceOffset: 3))
        #expect(player.coordinator.playhead.utteranceIndex == 2)
        #expect(reader.isFollowing)
        #expect(reader.chapterTitle == "Chapter 2")
        #expect(await reader.seek(toUtterance: 99, sourceOffset: 0) == false)
        #expect(reader.activeHighlight?.utteranceIndex == 2)
    }
}
