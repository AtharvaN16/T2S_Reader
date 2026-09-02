import Testing
@testable import T2SCore

@Suite struct FakeEngineTests {
    @Test func silenceOfKnownLengthWithWordTimings() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.1)
        let r = try await engine.synthesize(SynthesisRequest(spoken: "Hello big world", voiceID: "v"))
        #expect(r.audio.sampleRate == 24_000)
        #expect(r.audio.samples.count == 36_000)                         // 15 chars × 0.1 s × 24 kHz
        #expect(r.audio.samples.allSatisfy { $0 == 0 })
        #expect(r.wordTimings.map(\.spokenRange) == [0..<5, 6..<9, 10..<15])
        #expect(r.wordTimings.map(\.start) == [0.0, 0.6, 1.0])
        #expect(r.wordTimings.map(\.end) == [0.5, 0.9, 1.5])
        #expect(await engine.requests.count == 1)
    }

    @Test func failureInjection() async {
        let engine = FakeEngine()
        await engine.fail(on: "boom")
        await #expect(throws: SynthesisError.failed("boom")) {
            try await engine.synthesize(SynthesisRequest(spoken: "boom", voiceID: "v"))
        }
        _ = try? await engine.synthesize(SynthesisRequest(spoken: "fine", voiceID: "v"))
        #expect(await engine.requests.map(\.spoken) == ["boom", "fine"])
    }

    @Test func simulatedRTFAdvancesTheClock() async throws {
        let clock = ManualTimeSource()
        let engine = FakeEngine(secondsPerCharacter: 0.1, simulatedRTF: 0.5, timeSource: clock)
        _ = try await engine.synthesize(SynthesisRequest(spoken: "0123456789", voiceID: "v"))   // 1.0 s of audio
        #expect(clock.now() == 0.5)
    }

    @Test func silenceHelper() {
        let s = PCMAudio.silence(seconds: 0.2)
        #expect(s.samples.count == 4_800)
        #expect(s.duration == 0.2)
    }

    @Test func holdBlocksUntilReleased() async throws {
        let engine = FakeEngine()
        await engine.hold()
        let task = Task { try await engine.synthesize(SynthesisRequest(spoken: "x", voiceID: "v")) }
        await Task.yield()
        #expect(await engine.requests.isEmpty)                            // parked before recording
        await engine.release()
        _ = try await task.value
        #expect(await engine.requests.count == 1)
    }
}
