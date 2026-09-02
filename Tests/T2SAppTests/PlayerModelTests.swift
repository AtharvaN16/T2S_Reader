import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct PlayerModelTests {
    func makePlayer(_ f: AppFixtures) throws -> PlayerModel {
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        return PlayerModel(coordinator: coordinator, library: f.library)
    }

    @Test func loadExposesTimesChaptersAndScrubber() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let player = try makePlayer(f)
        await player.load(summary, play: false)
        #expect(player.current?.id == id)
        #expect(player.state == .paused)
        #expect(player.elapsed == 0 && player.total > 2)
        #expect(player.elapsedText == "0:00")
        #expect(player.totalText.hasPrefix("~"))                            // estimates until rendered
        #expect(player.chapters.map(\.title) == ["Chapter 1", "Chapter 2"])
        #expect(player.chapterIndex == 0)
        #expect(player.scrubber.tickCount == 48 && player.scrubber.fraction == 0)
        #expect(player.chapters[1].startSeconds > 0)
        #expect(player.renderError == nil)
    }

    @Test func transportAndSeeks() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let player = try makePlayer(f)
        await player.load(summary, play: true)
        #expect(player.isPlaying)
        await player.togglePlay()
        #expect(player.state == .paused)
        await player.seek(toChapter: 1)
        #expect(player.chapterIndex == 1)
        #expect(player.elapsed == player.chapters[1].startSeconds)
        await player.seek(fraction: 0)
        #expect(player.elapsed == 0 && player.chapterIndex == 0)
        await player.skip(by: 1)
        #expect(abs(player.elapsed - 1) < 1e-6)
        await player.skip(by: -30)
        #expect(player.elapsed == 0)
        await player.skip(by: 10_000)
        #expect(player.state == .finished)
        player.setRate(1.5)
        #expect(player.coordinator.rate == 1.5)
    }

    @Test func persistsRenderedChapters() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let player = try makePlayer(f)
        await player.load(summary, play: false)
        await player.coordinator.waitForRenderIdle()                        // 60 s window covers the whole fake book
        #expect(player.coordinator.timeline?.isFullyRendered == true)
        #expect(!player.isTotalApproximate)
        await player.persistRenderedChapters()
        let stored = try #require(try await f.store.timeline(for: id)).timeline
        #expect(stored.isFullyRendered)
        #expect(try await f.store.summary(id: id)?.isFullyRendered == true)
        await player.persistRenderedChapters()                              // no change: no extra writes (unobservable here; must not throw)
        #expect(player.renderError == nil)
    }

    @Test func loadingAnotherDocumentPersistsTheFirst() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake(), b = try await f.importFake()
        let player = try makePlayer(f)
        await player.load(try #require(try await f.store.summary(id: a)), play: false)
        await player.coordinator.waitForRenderIdle()
        await player.load(try #require(try await f.store.summary(id: b)), play: false)
        #expect(try await f.store.summary(id: a)?.isFullyRendered == true)
        #expect(player.current?.id == b)
    }

    @Test func localErrorClearsOnSuccessfulLoad() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let player = try makePlayer(f)
        await player.load(summary, play: false)
        let ghost = DocumentSummary(document: Document(title: "ghost", sourceType: .epub), chapterCount: 0,
                                    utteranceCount: 0, totalSeconds: 0, renderedCount: 0, isFinished: false,
                                    queueOrder: nil, lastPlayedAt: nil)
        await player.load(ghost, play: false)
        #expect(player.renderError == "Document is missing")
        await player.load(summary, play: false)
        #expect(player.renderError == nil)
    }
}
