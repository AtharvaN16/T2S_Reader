import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct SleepTimerTests {
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    func makePlayer(_ fixtures: AppFixtures) throws -> PlayerModel {
        let coordinator = PlaybackCoordinator(engine: FakeEngine(secondsPerCharacter: 0.05), store: fixtures.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: fixtures.store,
                                              timeSource: SystemTimeSource())
        return PlayerModel(coordinator: coordinator, library: fixtures.library)
    }

    @Test func minutesCountDownAndPause() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let player = try makePlayer(fixtures)
        await player.load(try #require(try await fixtures.store.summary(id: id)), play: true)
        let clock = Clock()
        let timer = SleepTimer(player: player) { clock.now }
        #expect(timer.active == nil && timer.caption == nil)
        timer.start(.minutes(10))
        #expect(timer.active == .minutes(10) && timer.remainingSeconds == 600 && timer.caption == "Ends in 10:00")
        clock.advance(599)
        timer.tick()
        #expect(player.isPlaying && timer.caption == "Ends in 0:01")
        clock.advance(2)
        timer.tick()
        #expect(!player.isPlaying && timer.active == nil && timer.caption == nil)
    }

    @Test func endOfChapterStopsWhenTheChapterChanges() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let player = try makePlayer(fixtures)
        await player.load(try #require(try await fixtures.store.summary(id: id)), play: true)
        let timer = SleepTimer(player: player) { Date() }
        timer.start(.endOfChapter)
        #expect(timer.caption == "Until the end of Chapter 1")
        timer.tick()
        #expect(player.isPlaying)
        await player.seek(toChapter: 1)
        timer.tick()
        #expect(!player.isPlaying && timer.active == nil)
    }

    @Test func cancelAndDocumentEnd() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let player = try makePlayer(fixtures)
        await player.load(try #require(try await fixtures.store.summary(id: id)), play: true)
        let timer = SleepTimer(player: player) { Date() }
        timer.start(.minutes(60))
        timer.cancel()
        #expect(timer.active == nil)
        timer.start(.minutes(60))
        await player.skip(by: 10_000)                                       // finishes the document
        timer.tick()
        #expect(timer.active == nil)
    }
}
