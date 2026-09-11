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

    /// Delete's path: the player forgets the document without saving anything, so nothing plays
    /// from — or writes into — a document the library is removing.
    @Test func unloadForgetsTheDocument() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let player = try makePlayer(f)
        await player.load(summary, play: true)
        #expect(player.isPlaying)
        player.unload()
        #expect(player.current == nil)
        #expect(player.state == .idle && !player.isPlaying)
        #expect(player.chapters.isEmpty && player.total == 0)
        #expect(player.renderError == nil)
        await player.coordinator.waitForRenderIdle()                        // the cleared plan settles; nothing hangs
        await player.persistRenderedChapters()                              // a no-op with nothing loaded
        #expect(try await f.store.summary(id: id)?.renderedCount == 0)
    }

    /// A foreground fill renders for minutes while the reader listens; the refs used to reach the
    /// store only on pause, lock, or the next load. `tick()` now writes the changed chapters every
    /// 30 s (Plan 18, Step 7), so a jetsam in front — and the Storage page — lag a fill by half a
    /// minute at most. The clock is manual: ten seconds is too soon, thirty-one is due.
    @Test func changedChaptersArePersistedEveryThirtySecondsWhilePlaying() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let clock = ManualTimeSource()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: clock)
        let player = PlayerModel(coordinator: coordinator, library: f.library, timeSource: clock)
        await player.load(summary, play: true)
        await coordinator.waitForRenderIdle()                               // the window's renders marked their chapters
        #expect(!coordinator.changedChapters.isEmpty)
        clock.advance(by: 10)
        player.tick()                                                       // too soon: nothing written
        await player.settlePersist()
        #expect(try await f.store.summary(id: id)?.renderedCount == 0)
        clock.advance(by: 21)
        player.tick()                                                       // 31 s since the load's write: due
        await player.settlePersist()
        #expect(try #require(try await f.store.summary(id: id)?.renderedCount) > 0)
        #expect(coordinator.changedChapters.isEmpty)
        clock.advance(by: 31)
        player.tick()                                                       // due again, but nothing changed: no write starts
        await player.settlePersist()
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

    /// The facts the 10 Hz bodies read are cached against the timeline revision (Plan 17): they still
    /// follow a seek, a render, and a load.
    @Test func derivedFactsFollowSeeksRendersAndLoads() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        await engine.hold()
        let player = try makePlayer(f, engine: engine)
        await player.load(summary, play: false)
        #expect(player.isTotalApproximate && player.chapterIndex == 0)
        #expect(player.chapters.map(\.fraction) == [0, 0])
        await player.seek(toChapter: 1)
        #expect(player.chapterIndex == 1)
        #expect(player.chapters[0].fraction == 1 && player.chapters[1].fraction == 0)
        let estimated = player.chapters.map(\.durationSeconds)
        await engine.release()
        player.renderWholeDocument()                                        // play-ahead alone renders nothing behind the seek
        await player.coordinator.waitForRenderIdle()
        #expect(!player.isTotalApproximate)                                 // the render moved the revision
        let timeline = try #require(player.coordinator.timeline)            // …and the axis with it: the actual durations
        let actual = ChapterEntry.entries(timeline: timeline, timeIndex: player.coordinator.timeIndex, elapsed: player.elapsed)
        #expect(player.chapters == actual && actual.map(\.durationSeconds) != estimated)
        let other = try await f.importFake()
        await player.load(try #require(try await f.store.summary(id: other)), play: false)
        #expect(player.isTotalApproximate && player.chapterIndex == 0)      // a load starts over
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

    /// A cache-hit `.rendered` carries no word timings (`RenderScheduler`), so a document the
    /// coordinator loaded before a prime flushed plays from the cache with empty timings in memory —
    /// and the next persist used to write that emptiness over the timings the prime had stored, so
    /// the first 30 s after an import highlighted nothing (the Plan 13 final review, finding 2).
    @Test func persistKeepsWordTimingsThePrimeStored() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        await engine.hold()                                                 // the coordinator renders nothing yet
        let player = try makePlayer(f, engine: engine)
        await player.load(summary, play: false)                             // estimates: no refs, no timings

        // Meanwhile a prime fills the audio cache and writes real word timings to the store.
        let runner = PrepareRunner(library: f.library, store: f.store, audioStore: f.audio,
                                   engine: FakeEngine(secondsPerCharacter: 0.05),
                                   defaults: UserDefaults(suiteName: "prepare-\(UUID())")!, arbiter: RenderArbiter())
        _ = await runner.prime(id)
        let primed = try #require(try await f.store.timeline(for: id)).timeline
        #expect(primed[utterance: 1].wordTimings?.isEmpty == false)

        await engine.release()
        await player.coordinator.waitForRenderIdle()                        // utterances 1 and 2 are cache hits
        #expect((player.coordinator.timeline?[utterance: 1].wordTimings ?? []).isEmpty)
        #expect(player.coordinator.timeline?[utterance: 1].audioRef == primed[utterance: 1].audioRef)

        await player.persistRenderedChapters()

        let stored = try #require(try await f.store.timeline(for: id)).timeline
        #expect(stored[utterance: 1].wordTimings == primed[utterance: 1].wordTimings)
        #expect(stored[utterance: 2].wordTimings == primed[utterance: 2].wordTimings)
        #expect(stored.isFullyRendered)
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
        #expect(bookmarks[0].note == "Sentence number 2 here.")             // the block of text it lands on
        #expect(player.isBookmarkedAtPlayhead)
    }

    @Test func toggleBookmarkAddsThenRemovesTheOneUnderThePlayhead() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let player = try makePlayer(f)
        #expect(await player.toggleBookmark() == false)                    // nothing loaded
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        #expect(!player.isBookmarkedAtPlayhead)
        #expect(await player.toggleBookmark())
        #expect(player.isBookmarkedAtPlayhead)
        #expect(try await f.store.bookmarks(for: id).count == 1)
        await player.seek(toChapter: 1)
        #expect(!player.isBookmarkedAtPlayhead)                             // another utterance
        await player.seek(toChapter: 0)
        #expect(player.isBookmarkedAtPlayhead)                              // back on the bookmarked one
        #expect(await player.toggleBookmark() == false)
        #expect(!player.isBookmarkedAtPlayhead)
        #expect(try await f.store.bookmarks(for: id).isEmpty)
    }

    @Test func loadReadsTheDocumentsBookmarksAndUnloadForgetsThem() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        try await f.store.add(Bookmark(documentID: id, position: Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0)))
        let player = try makePlayer(f)
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        #expect(!player.isBookmarkedAtPlayhead)
        await player.seek(toChapter: 1)
        #expect(player.isBookmarkedAtPlayhead)
        player.unload()
        #expect(player.bookmarkedUtterances.isEmpty)
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

    /// The fixed delivery is attached to the render, so every render key carries it and a book
    /// re-renders consistently; the reader's stored choice stays the plain voice.
    @Test func aKokoroVoiceRendersAtTheFixedDeliveryWhileTheStoredChoiceStaysPlain() async throws {
        let coreMLIdentity = "kokoro-coreml-2e878c6a-misaki1.0.6"
        let bella = "kokoro:kokoro-coreml-2e878c6a-misaki1.0.6:af_bella"
        let f = try AppFixtures()
        let id = try await f.importFake()
        var stored = try #require(try await f.store.document(id: id))
        stored.voiceID = bella
        try await f.store.update(stored)

        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let player = try makePlayer(f, engine: engine)
        player.voiceRouting = KokoroVoiceRouting(routes: [.init(engineIdentity: coreMLIdentity, isAvailable: { true })], defaultVoice: nil)
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.coordinator.waitForRenderIdle()

        let requested = Set(await engine.requests.map(\.voiceID))
        #expect(requested == ["\(bella)@1.25#\(Delivery.finish)"])
        #expect(player.coordinator.document?.voiceID == Delivery.applied(to: bella))
        #expect(try await f.store.document(id: id)?.voiceID == bella)
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
        #expect(requested == [Delivery.applied(to: heart)])
        #expect(player.coordinator.document?.voiceID == Delivery.applied(to: heart))
        // Nothing is written back — the reader never chose a voice, and the default may change.
        #expect(try await f.store.document(id: id)?.voiceID == nil)
    }

    @Test func aKokoroVoiceWhoseRuntimeIsMissingRendersWithTheKokoroDefaultVoice() async throws {
        let mlxIdentity = "kokoro-4e9ecdf0-mlx-misaki1.0.6"
        let mlxVoiceID = "kokoro:kokoro-4e9ecdf0-mlx-misaki1.0.6:af_bella"
        let coreMLIdentity = "kokoro-coreml-2e878c6a-misaki1.0.6"
        let heart = "kokoro:kokoro-coreml-2e878c6a-misaki1.0.6:af_heart"
        let f = try AppFixtures()
        let id = try await f.importFake()
        var stored = try #require(try await f.store.document(id: id))
        stored.voiceID = mlxVoiceID
        try await f.store.update(stored)

        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let player = try makePlayer(f, engine: engine)
        player.voiceRouting = KokoroVoiceRouting(
            routes: [
                .init(engineIdentity: coreMLIdentity, isAvailable: { true }),
                .init(engineIdentity: mlxIdentity, isAvailable: { false }),
            ],
            defaultVoice: heart
        )
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.coordinator.waitForRenderIdle()

        // Not the system voice: a document pinned to a runtime this phone cannot run still speaks
        // with Kokoro, through the default voice's own route (spec §5, §6).
        let requested = Set(await engine.requests.map(\.voiceID))
        #expect(requested == [Delivery.applied(to: heart)])
        #expect(player.coordinator.document?.voiceID == Delivery.applied(to: heart))
        // The stored choice is untouched, so the book returns to MLX on a phone that has it.
        #expect(try await f.store.document(id: id)?.voiceID == mlxVoiceID)
    }

    /// The Reader's voice chip reads this — the voice the loaded document actually plays with — rather
    /// than the summary the page was opened with, which a voice change never updates (owner,
    /// 2026-09-10: "when changing voice in reader, the reader voice UI does not update").
    @Test func routedVoiceFollowsLoadsAndVoiceChanges() async throws {
        let coreMLIdentity = "kokoro-coreml-2e878c6a-misaki1.0.6"
        let heart = "kokoro:\(coreMLIdentity):af_heart"
        let bella = "kokoro:\(coreMLIdentity):af_bella"
        let f = try AppFixtures()
        let id = try await f.importFake()
        let player = try makePlayer(f)
        #expect(player.routedVoiceID == nil)
        player.voiceRouting = KokoroVoiceRouting(routes: [.init(engineIdentity: coreMLIdentity, isAvailable: { true })], defaultVoice: heart)
        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        // The catalog's id: the route as resolved, without the delivery the render carries.
        #expect(player.routedVoiceID == heart)

        let change = VoiceChangeModel(library: f.library, player: player, libraryModel: LibraryModel(library: f.library))
        #expect(await change.apply(voiceID: bella, to: try #require(player.current)))
        #expect(player.routedVoiceID == bella)
        #expect(player.current?.document.voiceID == bella)

        player.unload()
        #expect(player.routedVoiceID == nil)
    }
}
