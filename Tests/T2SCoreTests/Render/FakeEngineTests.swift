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

    /// The default `synthesizeStreaming` wraps `synthesize`: one piece, then the timings.
    @Test func streamingDefaultIsOnePieceThenFinished() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.1)
        var chunks: [SynthesisChunk] = []
        for try await chunk in engine.synthesizeStreaming(SynthesisRequest(spoken: "abcd", voiceID: "v")) { chunks.append(chunk) }
        guard chunks.count == 2, case .piece(let audio, 0, true) = chunks[0], case .finished(let timings) = chunks[1] else {
            Issue.record("expected piece + finished, got \(chunks)"); return
        }
        #expect(abs(audio.duration - 0.4) < 1e-9)
        #expect(timings.count == 1)
    }

    /// An engine that says nothing about width renders one at a time.
    @Test func theProtocolDefaultWidthIsOne() {
        struct Minimal: SynthesisEngine {
            let engineID = "minimal"
            func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
                SynthesisResult(audio: .silence(seconds: 0.1), wordTimings: [])
            }
        }
        #expect(Minimal().maxConcurrentRenders(for: "anything") == 1)
    }

    @Test func aFakeReportsTheWidthItWasBuiltWith() {
        #expect(FakeEngine().maxConcurrentRenders(for: "v") == 1)
        #expect(FakeEngine(concurrentRenders: 4).maxConcurrentRenders(for: "v") == 4)
    }

    /// A fake that streams in pieces, holding between them so a test can watch the player start
    /// after the first: the pieces concatenate to exactly the whole render.
    @Test func streamsInPiecesThatConcatenateToTheWhole() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.1, pieceCount: 3)
        let whole = try await engine.synthesize(SynthesisRequest(spoken: "abcdefghij", voiceID: "v"))
        var pieces: [PCMAudio] = []
        var finished: [WordTiming]?
        for try await chunk in engine.synthesizeStreaming(SynthesisRequest(spoken: "abcdefghij", voiceID: "v")) {
            switch chunk {
            case .piece(let audio, let ordinal, let isLast):
                #expect(ordinal == pieces.count)
                #expect(isLast == (ordinal == 2))
                pieces.append(audio)
            case .finished(let timings): finished = timings
            }
        }
        #expect(pieces.count == 3)
        #expect(pieces.flatMap(\.samples) == whole.audio.samples)
        #expect(finished == whole.wordTimings)
    }

    @Test func holdBetweenPiecesParksTheStream() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.1, pieceCount: 2)
        await engine.holdBetweenPieces()
        let stream = engine.synthesizeStreaming(SynthesisRequest(spoken: "abcdef", voiceID: "v"))
        var iterator = stream.makeAsyncIterator()
        guard case .piece(_, 0, false)? = try await iterator.next() else { Issue.record("no first piece"); return }
        let second = Task { try await iterator.next() }
        // Poll (bounded) for the second piece to actually reach the park point, rather than a fixed
        // sleep racing `releasePiece()` against it.
        var parked = 0
        for _ in 0 ..< 20 {
            parked = await engine.parkedPieceCount
            if parked == 1 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(parked == 1)
        #expect(!second.isCancelled)
        await engine.releasePiece()
        guard case .piece(_, 1, true)? = try await second.value else { Issue.record("no second piece"); return }
    }

    /// Breaking out of the stream after the first piece cancels the underlying task
    /// (`continuation.onTermination`); a piece parked between pieces must resume and let that task
    /// observe cancellation and exit, rather than leak a parked continuation forever.
    @Test func aCancelledStreamDoesNotLeaveAPieceParked() async throws {
        let engine = FakeEngine(secondsPerCharacter: 0.1, pieceCount: 3)
        await engine.holdBetweenPieces()
        for try await chunk in engine.synthesizeStreaming(SynthesisRequest(spoken: "abcdefghi", voiceID: "v")) {
            if case .piece(_, 0, _) = chunk { break }
        }
        var parked = -1
        for _ in 0 ..< 20 {
            parked = await engine.parkedPieceCount
            if parked == 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(parked == 0)
        await engine.stopHoldingBetweenPieces()                           // must not hang
    }

    /// A failure surfaces through the stream exactly as it does through `synthesize`.
    @Test func streamingSurfacesAFailure() async throws {
        let engine = FakeEngine()
        await engine.fail(on: "boom")
        await #expect(throws: SynthesisError.failed("boom")) {
            for try await _ in engine.synthesizeStreaming(SynthesisRequest(spoken: "boom", voiceID: "v")) {}
        }
    }
}
