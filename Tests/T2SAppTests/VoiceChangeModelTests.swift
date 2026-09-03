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
}
