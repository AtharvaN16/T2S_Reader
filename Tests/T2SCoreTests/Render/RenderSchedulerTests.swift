import Foundation
import Testing
@testable import T2SCore

@Suite struct RenderSchedulerTests {
    let doc = UUID()
    func key(_ i: Int) -> RenderKey { RenderKey(documentID: doc, utteranceIndex: i, voiceID: "v", engineID: "fake", normalizerVersion: 1, segmenterVersion: 1) }
    func request(_ i: Int, _ spoken: String, stream: Bool = false) -> RenderRequest {
        RenderRequest(job: RenderJob(documentID: doc, utteranceIndex: i, tier: .playAhead), key: key(i), spoken: spoken, voiceID: "v", stream: stream)
    }

    /// Encodes successfully except for the very first call, which throws.
    final class ThrowOnceCodec: AudioCodec, @unchecked Sendable {
        let identifier = "throw-once"
        private var calls = 0
        private let inner = RawPCMCodec()
        func encode(_ pcm: PCMAudio) throws -> Data {
            calls += 1
            if calls == 1 { throw AudioCodecError.malformed }
            return try inner.encode(pcm)
        }
        func decode(_ data: Data) throws -> PCMAudio { try inner.decode(data) }
    }

    /// Collects events until `.idle` has been seen `idles` times.
    func collect(_ s: RenderScheduler, idles: Int = 1) async -> [RenderEvent] {
        var out: [RenderEvent] = []
        var seen = 0
        for await e in s.events {
            out.append(e)
            if e == .idle { seen += 1; if seen == idles { break } }
        }
        return out
    }

    @Test func rendersInOrderAndReportsDurations() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let s = RenderScheduler(engine: FakeEngine(secondsPerCharacter: 0.1), store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "abc"), request(1, "abcde")])
        let got = await events
        #expect(got == [
            .rendered(RenderedUtterance(documentID: doc, utteranceIndex: 0, key: key(0), duration: 0.3, wordTimings: [WordTiming(spokenRange: 0..<3, start: 0, end: 0.3)])),
            .rendered(RenderedUtterance(documentID: doc, utteranceIndex: 1, key: key(1), duration: 0.5, wordTimings: [WordTiming(spokenRange: 0..<5, start: 0, end: 0.5)])),
            .idle,
        ])
        let has0 = await store.contains(key(0))
        let has1 = await store.contains(key(1))
        #expect(has0 && has1)
    }

    @Test func cacheHitsAreReportedWithoutSynthesis() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        try await store.write(.silence(seconds: 1), for: key(0))
        let engine = FakeEngine()
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "already"), request(1, "new")])
        let got = await events
        #expect(got.count == 3)                                  // rendered(0 from cache), rendered(1), idle
        #expect(got[0] == .rendered(RenderedUtterance(documentID: doc, utteranceIndex: 0, key: key(0), duration: 1.0, wordTimings: [])))
        #expect(await engine.requests.map(\.spoken) == ["new"])
    }

    @Test func setPlanFlushesPendingWork() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let engine = FakeEngine()
        await engine.hold()                                        // utterance 0 parks inside the engine
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "a"), request(1, "b"), request(2, "c")])
        while await s.pending.count != 2 { await Task.yield() }   // 0 has been dequeued and is parked in the engine
        await s.setPlan([request(7, "z")])                       // seek: 1 and 2 must never render
        await engine.release()
        let got = await events
        let renderedIndices = got.compactMap { if case .rendered(let r) = $0 { return r.utteranceIndex } else { return nil } }
        #expect(renderedIndices == [0, 7])                         // in-flight finishes, flushed ones never start
        #expect(await s.pending.isEmpty)
    }

    @Test func failureInsertsSilenceAndContinues() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let engine = FakeEngine(secondsPerCharacter: 0.1)
        await engine.fail(on: "boom")
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "boom"), request(1, "ok")])
        let got = await events
        #expect(got[0] == .failed(documentID: doc, utteranceIndex: 0, message: "failed(\"boom\")"))
        #expect(got[1] == .rendered(RenderedUtterance(documentID: doc, utteranceIndex: 0, key: key(0), duration: 0.2, wordTimings: [])))
        if case .rendered(let r) = got[2] { #expect(r.utteranceIndex == 1 && r.duration == 0.2) } else { Issue.record("expected rendered 1") }
        #expect(try await store.read(key(0))?.duration == 0.2)
    }

    @Test func writeFailureFallsBackToSilence() async throws {
        let store = InMemoryAudioStore(codec: ThrowOnceCodec(), capacityBytes: 10_000_000)
        let s = RenderScheduler(engine: FakeEngine(secondsPerCharacter: 0.1), store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "abc")])
        let got = await events
        #expect(got.count == 3)
        if case .failed(_, let i, _) = got[0] { #expect(i == 0) } else { Issue.record("expected .failed first") }
        #expect(got[1] == .rendered(RenderedUtterance(documentID: doc, utteranceIndex: 0, key: key(0), duration: 0.2, wordTimings: [])))
        #expect(try await store.read(key(0))?.duration == 0.2)
    }

    @Test func storeFullPausesUntilResumed() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 100)   // nothing fits
        let s = RenderScheduler(engine: FakeEngine(secondsPerCharacter: 0.1), store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "abc"), request(1, "def")])
        let got = await events
        #expect(got == [.storeFull, .idle])
        #expect(await s.isPausedForStorage)
        #expect(await s.pending.isEmpty)
        await store.setCapacity(bytes: 10_000_000)
        async let more = collect(s)
        await s.resume()
        await s.setPlan([request(0, "abc")])
        let got2 = await more
        #expect(got2.count == 2 && got2.last == .idle)
        #expect(!(await s.isPausedForStorage))
    }

    @Test func measuresRollingRTF() async throws {
        let clock = ManualTimeSource()
        let engine = FakeEngine(secondsPerCharacter: 0.1, simulatedRTF: 0.25, timeSource: clock)
        let s = RenderScheduler(engine: engine, store: InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000), timeSource: clock, rtfWindow: 2)
        #expect(await s.measuredRTF == nil)
        async let events = collect(s)
        await s.setPlan([request(0, "aaaa"), request(1, "bbbbbbbb"), request(2, "cc")])
        _ = await events
        #expect(abs((await s.measuredRTF ?? 0) - 0.25) < 1e-9)
    }

    /// The engine's first render carries its lazy load — the stages, the G2P's lexicons, the voice
    /// table — so its ratio is the warm-up's, not the machine's. One such sample would pin the rate
    /// for a whole window, so it is offered and dropped: `measuredRTF` stays nil until the second.
    @Test func firstSampleIsNotRecorded() async throws {
        let clock = ManualTimeSource()
        let engine = FakeEngine(secondsPerCharacter: 0.1, simulatedRTF: 0.25, timeSource: clock)
        let s = RenderScheduler(engine: engine, store: InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000), timeSource: clock)
        async let first = collect(s)
        await s.setPlan([request(0, "aaaa")])
        _ = await first
        #expect(await s.measuredRTF == nil)

        async let second = collect(s)
        await s.setPlan([request(1, "bbbbbbbb")])
        _ = await second
        #expect(abs((await s.measuredRTF ?? 0) - 0.25) < 1e-9)
    }

    /// A streaming request yields its pieces as they finish, then the same `.rendered` a whole
    /// render would, and the store holds the concatenation (Plan 14).
    @Test func aStreamingRequestForwardsPiecesThenRenders() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let s = RenderScheduler(engine: FakeEngine(secondsPerCharacter: 0.1, pieceCount: 3), store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "abcdefghi", stream: true)])
        let got = await events
        #expect(got.count == 5)                                       // 3 pieces, rendered, idle
        for (i, e) in got.prefix(3).enumerated() {
            guard case .piece(let d, let index, let audio, let ordinal, let isLast) = e else { Issue.record("piece \(i): \(e)"); continue }
            #expect(d == doc && index == 0 && ordinal == i && isLast == (i == 2))
            #expect(abs(audio.duration - 0.3) < 1e-9)
        }
        guard case .rendered(let r) = got[3] else { Issue.record("no rendered: \(got[3])"); return }
        #expect(abs(r.duration - 0.9) < 1e-9 && r.wordTimings.count == 1)
        #expect(try await store.read(key(0))?.duration == 0.9)
    }

    /// A cache hit never streams: the clip is on disk, the player reads it from there.
    @Test func aStreamingRequestThatIsACacheHitYieldsNoPieces() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        try await store.write(.silence(seconds: 1), for: key(0))
        let s = RenderScheduler(engine: FakeEngine(pieceCount: 2), store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "already", stream: true)])
        let got = await events
        #expect(got.count == 2)                                       // rendered (from cache), idle
    }

    /// An engine that fails before its first piece: the key gets the failure silence, and `.failed`
    /// then `.rendered` follow as for any failure (spec §6).
    @Test func aStreamThatFailsStillRendersTheFailureSilence() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        let engine = FakeEngine(secondsPerCharacter: 0.1, pieceCount: 2)
        await engine.fail(on: "boom")
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "boom", stream: true)])
        let got = await events
        #expect(got.count == 3)                                       // failed, rendered(silence), idle
        guard case .failed = got[0], case .rendered(let r) = got[1] else { Issue.record("\(got)"); return }
        #expect(abs(r.duration - RenderScheduler.failureSilenceSeconds) < 1e-9)
    }
}
