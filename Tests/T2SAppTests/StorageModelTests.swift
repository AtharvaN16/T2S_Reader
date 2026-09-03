import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct StorageModelTests {
    func fresh() -> UserDefaults {
        let suite = "t2s-storage-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func statsRowsAndEviction() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake(), b = try await f.importFake()
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        let player = PlayerModel(coordinator: coordinator, library: f.library)
        let library = LibraryModel(library: f.library)
        let defaults = fresh()
        let storage = StorageModel(library: f.library, audioStore: f.audio, player: player, libraryModel: library, defaults: defaults)

        await player.load(try #require(try await f.store.summary(id: a)), play: false)
        await player.coordinator.waitForRenderIdle()
        await player.persistRenderedChapters()
        await storage.refresh()
        #expect(storage.stats.entries == 3 && storage.stats.bytes > 0)
        #expect(storage.rows.map(\.summary.id) == [a, b] || storage.rows.map(\.summary.id) == [b, a])
        #expect(storage.rows.first { $0.summary.id == a }?.renderedFraction == 1)
        #expect(storage.preparedSeconds > 0)
        #expect(storage.lastPrepareRun == nil)

        await storage.setCapacity(1_000_000)
        #expect(storage.stats.capacityBytes == 1_000_000)
        #expect(defaults.integer(forKey: AppPaths.audioCapacityKey) == 1_000_000)

        await storage.evict(a)
        #expect(player.current?.id == a && player.state == .paused)
        #expect(try await f.store.summary(id: a)?.renderedCount == 0)
        // Reloading immediately primes the paused document's render window, so cache entries can
        // already be fresh again. The stored timeline remains evicted until that new work is saved.

        let run = Date(timeIntervalSince1970: 1_700_000_000)
        storage.recordPrepareRun(run)
        #expect(storage.lastPrepareRun == run)
        #expect(defaults.object(forKey: StorageModel.lastPrepareRunKey) as? Date == run)
    }
}
