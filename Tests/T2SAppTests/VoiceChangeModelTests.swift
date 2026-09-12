import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct VoiceChangeModelTests {
    @Test func applyingAVoiceEvictsAudioAndPersistsTheOverride() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        let library = LibraryModel(library: f.library)
        let model = VoiceChangeModel(library: f.library, player: player, libraryModel: library)

        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.coordinator.waitForRenderIdle()
        await player.persistRenderedChapters()
        let before = try #require(try await f.store.summary(id: id))
        let discardedKey = try #require(player.coordinator.timeline?[utterance: 0].audioRef)
        #expect(model.discardedSeconds(for: before) > 0)

        #expect(await model.apply(voiceID: "custom-voice", to: before))
        let after = try #require(try await f.store.summary(id: id))
        #expect(after.document.voiceID == "custom-voice" && after.renderedCount == 0)
        #expect(await f.audio.contains(RenderKey(rawValue: discardedKey)) == false)
        #expect(player.current?.id == id && player.coordinator.document?.voiceID == "custom-voice")
        #expect(model.discardedSeconds(for: after) == 0)

        #expect(await model.apply(voiceID: nil, to: after))
        #expect(try await f.store.document(id: id)?.voiceID == nil)
    }

    @Test func applyingTheUnchangedVoiceKeepsRenderedAudio() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        let library = LibraryModel(library: f.library)
        let model = VoiceChangeModel(library: f.library, player: player, libraryModel: library)

        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.coordinator.waitForRenderIdle()
        await player.persistRenderedChapters()
        let summary = try #require(try await f.store.summary(id: id))
        let renderedKey = try #require(player.coordinator.timeline?[utterance: 0].audioRef)

        #expect(await model.apply(voiceID: nil, to: summary))
        #expect(try await f.store.summary(id: id)?.renderedCount == summary.renderedCount)
        #expect(await f.audio.contains(RenderKey(rawValue: renderedKey)))
    }

    /// `force` is what "Make default" needs: it moves the default and clears the override, and for
    /// a document that was already following the default that is no change to the stored value —
    /// but the voice it speaks in has moved, so the audio still has to go.
    @Test func forcingReloadsEvenWhenTheStoredVoiceIsUnchanged() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        let model = VoiceChangeModel(library: f.library, player: player, libraryModel: LibraryModel(library: f.library))

        await player.load(try #require(try await f.store.summary(id: id)), play: false)
        await player.coordinator.waitForRenderIdle()
        await player.persistRenderedChapters()
        let summary = try #require(try await f.store.summary(id: id))
        #expect(summary.document.voiceID == nil && summary.renderedCount > 0)

        // The stored count going to zero is the eviction: the unforced call on the same document
        // (`applyingTheUnchangedVoiceKeepsRenderedAudio`) leaves it where it was. The blobs
        // themselves are not checked, because the reload renders the very same keys straight back
        // when — as here, with no Settings change under the test — the effective voice has not
        // actually moved.
        #expect(await model.apply(voiceID: nil, to: summary, force: true))
        #expect(try await f.store.summary(id: id)?.renderedCount == 0)
    }

    /// The Reader's sheet changes the voice under a playing document and expects to hear the new
    /// one: the reload picks the playhead back up rather than leaving the page silent.
    @Test func resumingPlaybackCarriesAPlayingDocumentThroughTheChange() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        let model = VoiceChangeModel(library: f.library, player: player, libraryModel: LibraryModel(library: f.library))

        await player.load(try #require(try await f.store.summary(id: id)), play: true)
        await player.coordinator.waitForRenderIdle()
        #expect(player.isPlaying)
        let summary = try #require(try await f.store.summary(id: id))

        #expect(await model.apply(voiceID: "custom-voice", to: summary, resumingPlayback: true))
        #expect(player.isPlaying)
    }

    /// …and without the flag it does not, because most destructive changes are not a listener
    /// swapping the voice mid-chapter: deleting rendered audio from Storage leaves the player as
    /// it found it.
    @Test func withoutResumingPlaybackTheChangeLeavesThePlayerPaused() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        let model = VoiceChangeModel(library: f.library, player: player, libraryModel: LibraryModel(library: f.library))

        await player.load(try #require(try await f.store.summary(id: id)), play: true)
        await player.coordinator.waitForRenderIdle()
        #expect(player.isPlaying)
        let summary = try #require(try await f.store.summary(id: id))

        #expect(await model.apply(voiceID: "custom-voice", to: summary))
        #expect(player.isPlaying == false)
    }
}
