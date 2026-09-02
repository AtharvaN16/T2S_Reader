import Foundation
import Testing
@testable import T2SCore

@Suite struct RenderSchedulerTests {
    let doc = UUID()
    func key(_ i: Int) -> RenderKey { RenderKey(documentID: doc, utteranceIndex: i, voiceID: "v", engineID: "fake", normalizerVersion: 1, segmenterVersion: 1) }
    func request(_ i: Int, _ spoken: String) -> RenderRequest {
        RenderRequest(job: RenderJob(documentID: doc, utteranceIndex: i, tier: .playAhead), key: key(i), spoken: spoken, voiceID: "v")
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

    @Test func skipsKeysTheStoreAlreadyHolds() async throws {
        let store = InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000)
        try await store.write(.silence(seconds: 1), for: key(0))
        let engine = FakeEngine()
        let s = RenderScheduler(engine: engine, store: store, timeSource: ManualTimeSource())
        async let events = collect(s)
        await s.setPlan([request(0, "already"), request(1, "new")])
        let got = await events
        #expect(got.count == 2)                                  // one rendered + idle
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
}
