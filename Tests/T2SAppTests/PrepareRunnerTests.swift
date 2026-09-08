import Foundation
import Testing
import T2SAudio
import T2SCore
@testable import T2SApp

@MainActor
@Suite struct PrepareRunnerTests {
    @Test func continueThenQueueConsumesOneSharedPlaybackBudgetAndRecordsRun() async throws {
        let fixtures = try AppFixtures()
        let first = try await fixtures.importFake()
        let second = try await fixtures.importFake()
        let suite = "prepare-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(1.0, forKey: AppPaths.prepareBudgetKey)
        let runner = PrepareRunner(library: fixtures.library, store: fixtures.store, audioStore: fixtures.audio,
                                   engine: FakeEngine(secondsPerCharacter: 0.05), defaults: defaults,
                                   arbiter: RenderArbiter())

        let result = await runner.run(lastPlayed: first, queue: [first, second],
                                      device: DeviceState(charging: true, thermalSerious: false,
                                                          lowPowerMode: false, storeFull: false))

        #expect(result.renderedUtterances > 0 && result.documentIDs.first == first)
        #expect(defaults.object(forKey: StorageModel.lastPrepareRunKey) as? Date != nil)
    }

    @Test func unsafeDeviceDoesNoWorkAndDoesNotClaimARun() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let defaults = UserDefaults(suiteName: "prepare-\(UUID())")!
        let runner = PrepareRunner(library: fixtures.library, store: fixtures.store, audioStore: fixtures.audio,
                                   engine: FakeEngine(), defaults: defaults, arbiter: RenderArbiter())

        let result = await runner.run(lastPlayed: id, queue: [id], device: .unplugged)

        #expect(result.renderedUtterances == 0)
        #expect(defaults.object(forKey: StorageModel.lastPrepareRunKey) == nil)
    }

    @Test func anUnavailableKokoroVoicePreparesTheWholeDocumentWithTheSystemDefault() async throws {
        let kokoroVoiceID = "kokoro:kokoro-4e9ecdf0-mlx-misaki1.0.6:af_heart"
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        var stored = try #require(try await fixtures.store.document(id: id))
        stored.voiceID = kokoroVoiceID
        try await fixtures.store.update(stored)

        let suite = "prepare-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let runner = PrepareRunner(library: fixtures.library, store: fixtures.store, audioStore: fixtures.audio,
                                   engine: engine, defaults: defaults, arbiter: RenderArbiter())
        runner.voiceRouting = KokoroVoiceRouting.unavailable

        let result = await runner.run(lastPlayed: id, queue: [id],
                                      device: DeviceState(charging: true, thermalSerious: false,
                                                          lowPowerMode: false, storeFull: false))

        #expect(result.renderedUtterances > 0)
        let requested = Set(await engine.requests.map(\.voiceID))
        #expect(requested == ["default"])
        #expect(try await fixtures.store.document(id: id)?.voiceID == kokoroVoiceID)
    }

    @Test func aDocumentWithNoVoiceOfItsOwnPreparesWithTheKokoroDefaultVoice() async throws {
        let coreMLIdentity = "kokoro-coreml-2e878c6a-misaki1.0.6"
        let heart = "kokoro:kokoro-coreml-2e878c6a-misaki1.0.6:af_heart"
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        #expect(try await fixtures.store.document(id: id)?.voiceID == nil)

        let suite = "prepare-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let runner = PrepareRunner(library: fixtures.library, store: fixtures.store, audioStore: fixtures.audio,
                                   engine: engine, defaults: defaults, arbiter: RenderArbiter())
        runner.voiceRouting = KokoroVoiceRouting(
            routes: [.init(engineIdentity: coreMLIdentity, isAvailable: { true })],
            defaultVoice: heart
        )

        let result = await runner.run(lastPlayed: id, queue: [id],
                                      device: DeviceState(charging: true, thermalSerious: false,
                                                          lowPowerMode: false, storeFull: false))

        // The same render key playback will ask for, so the prepared audio is the audio it plays.
        #expect(result.renderedUtterances > 0)
        let requested = Set(await engine.requests.map(\.voiceID))
        #expect(requested == [heart])
        #expect(try await fixtures.store.document(id: id)?.voiceID == nil)
    }

    /// Spec §3.4.1 tier 2: the first 30 s of a document, any power state, so its first tap plays
    /// with no spin-up. Never planned by anything until Plan 13 (the audit's #3).
    @Test func primeRendersTheFirstThirtySecondsOnBattery() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let defaults = UserDefaults(suiteName: "prepare-\(UUID())")!
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let runner = PrepareRunner(library: fixtures.library, store: fixtures.store, audioStore: fixtures.audio,
                                   engine: engine, defaults: defaults, arbiter: RenderArbiter())

        let result = await runner.prime(id)

        #expect(result.reason == .prime)
        #expect(result.stopReason == .completed)
        #expect(result.renderedUtterances == 3)                                  // the fake book is ~3.3 s: all of it
        #expect(result.documentIDs == [id])
        #expect(result.recordedAt == nil)                                       // a prime is not a Prepare run
        #expect(defaults.object(forKey: StorageModel.lastPrepareRunKey) == nil)
        let stored = try #require(try await fixtures.store.timeline(for: id)).timeline
        let refs = stored.chapters.flatMap(\.utterances).map(\.audioRef)
        #expect(refs.allSatisfy { $0 != nil })
    }

    /// The continue-document is whichever was played last; nothing played means nothing to prime.
    @Test func primeContinueDocumentPicksTheLastPlayed() async throws {
        let fixtures = try AppFixtures()
        let first = try await fixtures.importFake()
        let second = try await fixtures.importFake()
        let defaults = UserDefaults(suiteName: "prepare-\(UUID())")!
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let runner = PrepareRunner(library: fixtures.library, store: fixtures.store, audioStore: fixtures.audio,
                                   engine: engine, defaults: defaults, arbiter: RenderArbiter())

        let nothing = await runner.primeContinueDocument()
        #expect(nothing.stopReason == .completed && nothing.renderedUtterances == 0)

        try await fixtures.store.savePosition(Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0, charOffset: 0), for: second)
        let primed = await runner.primeContinueDocument()
        #expect(primed.documentIDs == [second])
        #expect(primed.renderedUtterances > 0)
        _ = first
    }
}
