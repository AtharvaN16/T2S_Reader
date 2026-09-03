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

    @Test func resolvesTheUtteranceUnderTheTap() {
        let t = epubTimeline
        let block = "First sentence. Second sentence here."
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: block, offsetInBlock: 3), in: t) == 0)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: block, offsetInBlock: 20), in: t) == 1)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: block, offsetInBlock: 15), in: t) == 1) // on the gap: next start ≤ offset wins
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: "Another block.", offsetInBlock: 5), in: t) == 2)
    }

    @Test func whitespaceIsNormalizedOnBothSides() {
        let t = epubTimeline
        let raw = "  First   sentence.\n\n  Second\tsentence here.  "
        #expect(ReaderModel.normalized(raw) == "First sentence. Second sentence here.")
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: raw, offsetInBlock: 4), in: t) == 0)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: raw, offsetInBlock: 26), in: t) == 1)
    }

    @Test func unknownTextOrResourceYieldsNil() {
        let t = epubTimeline
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch9.xhtml", blockText: "First sentence.", offsetInBlock: 0), in: t) == nil)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: "Not in the book.", offsetInBlock: 0), in: t) == nil)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: "OEBPS/ch1.xhtml", blockText: "", offsetInBlock: 0), in: t) == nil)
    }

    @Test func pdfTapsResolveByPage() {
        let href = PDFDocumentReader.resourceHref
        let t = Timeline(chapters: [Chapter(title: "Doc", position: Position(resourceHref: href, progression: 0), utterances: [
            utterance("Page one.", href: href, offset: 0, progression: 0),
            utterance("Page two, first.", href: href, offset: 10, progression: 0.5),
            utterance("Page two, second.", href: href, offset: 27, progression: 0.5),
        ])])
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: href, blockText: "", offsetInBlock: 0, pageIndex: 1), in: t) == 1)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: href, blockText: "", offsetInBlock: 0, pageIndex: 0), in: t) == 0)
        #expect(ReaderModel.utteranceIndex(for: SourceHit(resourceHref: href, blockText: "", offsetInBlock: 0, pageIndex: 5), in: t) == nil)
    }

    @Test func seekingAndFollowing() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        let reader = ReaderModel(player: player)
        #expect(reader.isFollowing)
        #expect(reader.chapterTitle == "Chapter 1")
        reader.suspendFollowing()
        #expect(!reader.isFollowing)
        let hit = SourceHit(resourceHref: "OEBPS/ch2.xhtml", blockText: "Sentence number 2 here.", offsetInBlock: 3)
        #expect(await reader.seek(to: hit))
        #expect(player.coordinator.playhead.utteranceIndex == 2)
        #expect(reader.isFollowing)                                         // a tap re-engages following
        #expect(reader.chapterTitle == "Chapter 2")
        #expect(await reader.seek(to: SourceHit(resourceHref: "nope", blockText: "x", offsetInBlock: 0)) == false)
        #expect(reader.activeHighlight?.utteranceIndex == 2)
    }
}
