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
}
