import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct QueueContinuationTests {
    func fresh() -> UserDefaults {
        let suite = "t2s-prefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func advancesToTheNextQueuedDocumentWhenFinished() async throws {
        let fixtures = try AppFixtures()
        let a = try await fixtures.importFake()
        let b = try await fixtures.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: fixtures.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: fixtures.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: fixtures.library)
        let library = LibraryModel(library: fixtures.library)
        await library.refresh()
        let preferences = ReaderPreferences(defaults: fresh())
        let continuation = QueueContinuation(player: player, library: library, preferences: preferences)

        await player.load(try #require(try await fixtures.store.summary(id: a)), play: true)
        #expect(await continuation.advanceIfFinished() == false)             // still playing
        await player.skip(by: 10_000)
        #expect(player.state == .finished)
        #expect(await continuation.advanceIfFinished())
        #expect(player.current?.id == b && player.isPlaying)
        await player.skip(by: 10_000)
        #expect(await continuation.advanceIfFinished() == false)             // nothing after b
        #expect(player.current?.id == b)

        preferences.autoplayNext = false
        await player.load(try #require(try await fixtures.store.summary(id: a)), play: true)
        await player.skip(by: 10_000)
        #expect(await continuation.advanceIfFinished() == false)
        #expect(player.current?.id == a)
    }
}
