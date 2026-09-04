import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct PlayerModelTests {
    func makePlayer(_ f: AppFixtures, engine: FakeEngine = FakeEngine(secondsPerCharacter: 0.05)) throws -> PlayerModel {
        let coordinator = PlaybackCoordinator(engine: engine, store: f.audio,
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
        // Held engine: nothing renders while the transport assertions run, so the time axis stays
        // the estimated one they were written against (a landing `.rendered` swaps an estimated
        // duration for an actual one and moves every time after it).
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        await engine.hold()
        let player = try makePlayer(f, engine: engine)
        await player.load(summary, play: true)
        #expect(player.isPlaying)                                           // .catchingUp until the head renders
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
        await engine.release()
        await player.coordinator.waitForRenderIdle()                        // the axis may move now; the end of it is still the end
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

    @Test func destructiveChangePersistsThenReloadsTheCurrentDocument() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let player = try makePlayer(f)
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.coordinator.waitForRenderIdle()

        #expect(await player.performDestructiveChange(for: id) {
            try await f.library.evictAudio(for: id)
        })

        #expect(try await f.store.summary(id: id)?.renderedCount == 0)
        #expect(try await f.store.timeline(for: id)?.timeline[utterance: 0].audioRef == nil)
        #expect(player.current?.id == id && player.state == .paused)
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

    @Test func addBookmarkStoresTheCurrentPosition() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let player = try makePlayer(f)
        #expect(await player.addBookmark() == false)                       // nothing loaded
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.seek(toChapter: 1)
        #expect(await player.addBookmark())
        let bookmarks = try await f.store.bookmarks(for: id)
        #expect(bookmarks.count == 1)
        #expect(bookmarks[0].position.resourceHref == "OEBPS/ch2.xhtml")
    }

    @Test func defaultVoiceAppliesOnlyWithoutAnOverride() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let player = try makePlayer(f)
        player.defaultVoiceID = "com.apple.voice.compact.en-US.Samantha"
        let summary = try #require(try await f.store.summary(id: id))
        await player.load(summary, play: false)
        #expect(player.coordinator.document?.voiceID == "com.apple.voice.compact.en-US.Samantha")
        var overridden = summary.document
        overridden.voiceID = "custom"
        try await f.store.update(overridden)
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        #expect(player.coordinator.document?.voiceID == "custom")
        #expect(try await f.store.document(id: id)?.voiceID == "custom")
    }

    @Test func anUnavailableKokoroVoiceRendersTheWholeDocumentWithTheSystemDefault() async throws {
        let kokoroVoiceID = "kokoro:kokoro-4e9ecdf0-mlx-misaki1.0.6:af_heart"
        let f = try AppFixtures()
        let id = try await f.importFake()
        var stored = try #require(try await f.store.document(id: id))
        stored.voiceID = kokoroVoiceID
        try await f.store.update(stored)

        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let player = try makePlayer(f, engine: engine)
        player.voiceRouting = KokoroVoiceRouting.unavailable
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.coordinator.waitForRenderIdle()

        // Decided once, before planning: every utterance of the book renders with the system default.
        let requested = Set(await engine.requests.map(\.voiceID))
        #expect(requested == ["default"])
        #expect(player.coordinator.document?.voiceID == "default")
        // The stored choice is untouched, so the book returns to Kokoro when the engine is available.
        #expect(try await f.store.document(id: id)?.voiceID == kokoroVoiceID)
    }

    @Test func aDocumentWithNoVoiceOfItsOwnRendersWithTheKokoroDefaultVoice() async throws {
        let coreMLIdentity = "kokoro-coreml-2e878c6a-misaki1.0.6"
        let heart = "kokoro:kokoro-coreml-2e878c6a-misaki1.0.6:af_heart"
        let f = try AppFixtures()
        let id = try await f.importFake()
        #expect(try await f.store.document(id: id)?.voiceID == nil)

        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let player = try makePlayer(f, engine: engine)
        player.voiceRouting = KokoroVoiceRouting(
            routes: [.init(engineIdentity: coreMLIdentity, isAvailable: { true })],
            defaultVoice: heart
        )
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.coordinator.waitForRenderIdle()

        // Decided once, before planning, exactly like the fallback: the whole book renders on Kokoro.
        let requested = Set(await engine.requests.map(\.voiceID))
        #expect(requested == [heart])
        #expect(player.coordinator.document?.voiceID == heart)
        // Nothing is written back — the reader never chose a voice, and the default may change.
        #expect(try await f.store.document(id: id)?.voiceID == nil)
    }
}
