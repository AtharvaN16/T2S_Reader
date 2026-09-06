import Foundation
import Testing
import T2SAudio
import T2SCore
@testable import T2SApp

@MainActor
@Suite struct VoicePreviewModelTests {
    private let voiceA = "kokoro:test-engine:af_heart"
    private let voiceB = "kokoro:test-engine:bf_emma"

    @Test func togglingRendersThenPlaysTheSampleInTheRequestedVoice() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let factory = PlayerFactory()
        let model = VoicePreviewModel(engine: engine, makePlayer: { factory.make($0) }, beforePreview: {})

        model.toggle(voiceA)
        while model.isRendering { await Task.yield() }

        #expect(model.previewing == voiceA)
        let requests = await engine.requests
        #expect(requests.map(\.voiceID) == [voiceA])
        #expect(requests.map(\.spoken) == [VoicePreviewModel.sampleText])
        #expect(factory.made.count == 1)
        #expect(factory.made[0].playCount == 1)
        #expect(factory.made[0].enqueued.map(\.tag) == [0])
    }

    @Test func togglingTheSameIDWhilePlayingStopsAndClears() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let factory = PlayerFactory()
        let model = VoicePreviewModel(engine: engine, makePlayer: { factory.make($0) }, beforePreview: {})

        model.toggle(voiceA)
        while model.isRendering { await Task.yield() }
        #expect(model.previewing == voiceA)

        model.toggle(voiceA)
        #expect(model.previewing == nil)
        #expect(model.isRendering == false)
        #expect(factory.made[0].resetCount == 1)
    }

    @Test func togglingAnotherIDStopsTheFirstAndPreviewsTheSecond() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let factory = PlayerFactory()
        let model = VoicePreviewModel(engine: engine, makePlayer: { factory.make($0) }, beforePreview: {})

        model.toggle(voiceA)
        while model.isRendering { await Task.yield() }
        model.toggle(voiceB)
        while model.isRendering { await Task.yield() }

        #expect(model.previewing == voiceB)
        #expect(factory.made[0].resetCount == 1)
        #expect(factory.made.count == 2)
        let requests = await engine.requests
        #expect(requests.map(\.voiceID) == [voiceA, voiceB])
    }

    @Test func thePlayersOnSegmentFinishedClearsPreviewing() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let factory = PlayerFactory()
        let model = VoicePreviewModel(engine: engine, makePlayer: { factory.make($0) }, beforePreview: {})

        model.toggle(voiceA)
        while model.isRendering { await Task.yield() }
        #expect(model.previewing == voiceA)

        factory.made[0].onSegmentFinished?(0)
        #expect(model.previewing == nil)
    }

    @Test func anEngineFailureSetsLastErrorAndClearsPreviewing() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        await engine.fail(on: VoicePreviewModel.sampleText)
        let factory = PlayerFactory()
        let model = VoicePreviewModel(engine: engine, makePlayer: { factory.make($0) }, beforePreview: {})

        model.toggle(voiceA)
        while model.isRendering { await Task.yield() }

        #expect(model.previewing == nil)
        #expect(model.lastError != nil)
        #expect(factory.made.isEmpty)
    }

    @Test func theNextToggleClearsAnEarlierFailure() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        await engine.fail(on: VoicePreviewModel.sampleText)
        let factory = PlayerFactory()
        let model = VoicePreviewModel(engine: engine, makePlayer: { factory.make($0) }, beforePreview: {})

        model.toggle(voiceA)
        while model.isRendering { await Task.yield() }
        #expect(model.lastError != nil)

        model.toggle(voiceB)
        #expect(model.lastError == nil)
    }

    @Test func stoppingWhileTheBookIsBeingPausedNeverAsksTheEngine() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let gate = Gate()
        let factory = PlayerFactory()
        let model = VoicePreviewModel(engine: engine, makePlayer: { factory.make($0) }, beforePreview: { await gate.wait() })

        model.toggle(voiceA)
        await Task.yield()
        model.stop()
        await gate.open()
        await Task.yield()
        await Task.yield()

        #expect(await engine.requests.isEmpty)
        #expect(factory.made.isEmpty)
        #expect(model.previewing == nil)
    }

    @Test func beforePreviewIsAwaitedBeforeTheEngineIsAsked() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        let gate = Gate()
        let factory = PlayerFactory()
        let model = VoicePreviewModel(engine: engine, makePlayer: { factory.make($0) }, beforePreview: { await gate.wait() })

        model.toggle(voiceA)
        await Task.yield()
        await Task.yield()
        #expect(await engine.requests.isEmpty)

        await gate.open()
        while model.isRendering { await Task.yield() }
        let requests = await engine.requests
        #expect(requests.map(\.voiceID) == [voiceA])
    }

    @Test func stopCancelsAnInFlightRenderSoItsAudioNeverPlays() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        await engine.hold()
        let factory = PlayerFactory()
        let model = VoicePreviewModel(engine: engine, makePlayer: { factory.make($0) }, beforePreview: {})

        model.toggle(voiceA)
        await Task.yield()
        #expect(model.isRendering)

        model.stop()
        #expect(model.previewing == nil)
        #expect(model.isRendering == false)

        await engine.release()
        await Task.yield()
        await Task.yield()

        #expect(factory.made.isEmpty)
    }
}

/// Records every player `VoicePreviewModel` builds, so a test can inspect each one.
@MainActor
private final class PlayerFactory {
    private(set) var made: [FakePreviewPlayer] = []

    func make(_ sampleRate: Double) -> any AudioPlaying {
        let player = FakePreviewPlayer()
        made.append(player)
        return player
    }
}

/// A minimal `AudioPlaying` double: no timing, just enough to see what the model asked of it.
@MainActor
private final class FakePreviewPlayer: AudioPlaying {
    var rate: Double = 1
    private(set) var isPlaying = false
    var consumedSeconds: TimeInterval = 0
    var onSegmentFinished: ((Int) -> Void)?
    private(set) var enqueued: [(audio: PCMAudio, tag: Int)] = []
    private(set) var playCount = 0
    private(set) var resetCount = 0

    func enqueue(_ audio: PCMAudio, tag: Int) { enqueued.append((audio, tag)) }
    func play() { isPlaying = true; playCount += 1 }
    func pause() { isPlaying = false }
    func reset() { enqueued.removeAll(); isPlaying = false; resetCount += 1 }
    func rebuildAfterMediaServicesReset() {}
}

/// Blocks `beforePreview` until the test explicitly lets it through, to prove the model awaits it
/// before asking the engine for anything.
private actor Gate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
