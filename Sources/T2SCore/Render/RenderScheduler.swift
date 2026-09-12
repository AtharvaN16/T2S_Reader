import Foundation

public struct RenderRequest: Hashable, Sendable {
    public var job: RenderJob
    public var key: RenderKey
    public var spoken: String
    public var voiceID: String
    /// Render in pieces and forward each as a `.piece` event: the utterance the player is waiting on
    /// (Plan 14). Everything else renders whole.
    public var stream: Bool
    public init(job: RenderJob, key: RenderKey, spoken: String, voiceID: String, stream: Bool = false) {
        self.job = job
        self.key = key
        self.spoken = spoken
        self.voiceID = voiceID
        self.stream = stream
    }
}

public struct RenderedUtterance: Hashable, Sendable {
    public var documentID: UUID
    public var utteranceIndex: Int
    public var key: RenderKey
    /// Actual duration at 1x.
    public var duration: TimeInterval
    public var wordTimings: [WordTiming]
    public init(documentID: UUID, utteranceIndex: Int, key: RenderKey, duration: TimeInterval, wordTimings: [WordTiming]) {
        self.documentID = documentID
        self.utteranceIndex = utteranceIndex
        self.key = key
        self.duration = duration
        self.wordTimings = wordTimings
    }
}

public enum RenderEvent: Hashable, Sendable {
    /// A piece of a streaming render, in order, before its `.rendered`; the pieces concatenate to
    /// the clip stored under the key. `isLast` marks the piece the player's completion belongs to.
    case piece(documentID: UUID, utteranceIndex: Int, audio: PCMAudio, ordinal: Int, isLast: Bool)
    /// A cache hit (the store already held the key) also produces this, with empty word timings.
    case rendered(RenderedUtterance)
    /// Spec §6: logged; 200 ms of silence is stored under the key and a `.rendered` follows,
    /// unless storing the silence itself failed, in which case nothing follows.
    case failed(documentID: UUID, utteranceIndex: Int, message: String)
    /// Spec §6: the store refused the entry; rendering pauses until `resume()`.
    case storeFull
    /// The plan is empty (backpressure, spec §3.4).
    case idle
}

/// Executor of `RenderRequest`s, one batch at a time — a batch as wide as the engine allows, one
/// for anything on the device (spec §3.4). Knows nothing about timelines: the coordinator turns
/// policy jobs into requests and applies the events.
public actor RenderScheduler {
    public typealias Sleeper = @Sendable (TimeInterval) async -> Void
    public static let failureSilenceSeconds: TimeInterval = 0.2

    public nonisolated let events: AsyncStream<RenderEvent>
    private let continuation: AsyncStream<RenderEvent>.Continuation
    private let engine: any SynthesisEngine
    private let store: any AudioStore
    private let timeSource: any TimeSource
    private let rtfWindow: Int
    private let arbiter: RenderArbiter
    /// Holds a background render until the process's CPU fits iOS's limit (``CPUBudget``); nil
    /// renders unpaced, which is what tests and the everyday build want.
    private let budget: CPUBudget?
    /// Maximum generated-audio seconds per wall second for the non-urgent foreground fill. Nil
    /// leaves that tier unpaced; the urgent play-ahead tier never waits here.
    private let foregroundFillRate: Double?
    private let foregroundFillSleeper: Sleeper
    private var foregroundFillDelay: TimeInterval = 0
    /// What the last synthesis cost in CPU seconds — the estimate the budget is asked to fit next
    /// time. A render before the first is guessed at ``firstRenderCPUEstimate``.
    private var lastRenderCPUSeconds: TimeInterval?
    static let firstRenderCPUEstimate: TimeInterval = 5

    public private(set) var pending: [RenderRequest] = []
    public private(set) var isPausedForStorage = false
    private var running = false
    /// Direct cancellation prevents a request that was waiting on the shared lease from starting.
    /// An already synthesizing/writing request is intentionally allowed to finish atomically.
    private var isCancelled = false
    private var rtfSamples: [Double] = []
    /// The engine's first render carries its lazy load — the stages, the G2P's lexicons, the voice
    /// table — so its ratio measures the warm-up, not the machine. One such sample (RTF 3–20 on a
    /// cold A13) would pin the rate for a whole window, so the first is offered and dropped.
    private var hasSkippedFirstSample = false

    public init(engine: any SynthesisEngine, store: any AudioStore, timeSource: any TimeSource,
                rtfWindow: Int = 20, arbiter: RenderArbiter = RenderArbiter(), budget: CPUBudget? = nil,
                foregroundFillRate: Double? = nil,
                foregroundFillSleeper: @escaping Sleeper = { seconds in try? await Task.sleep(for: .seconds(seconds)) }) {
        self.engine = engine
        self.store = store
        self.timeSource = timeSource
        self.rtfWindow = max(1, rtfWindow)
        self.arbiter = arbiter
        self.budget = budget
        self.foregroundFillRate = foregroundFillRate.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.foregroundFillSleeper = foregroundFillSleeper
        (events, continuation) = AsyncStream.makeStream(of: RenderEvent.self, bufferingPolicy: .unbounded)
    }

    /// Rolling mean of synth seconds per audio second over the last `rtfWindow` renders, the first
    /// of the session excluded (it carries the engine's lazy load). Nil until the second render.
    public var measuredRTF: Double? {
        rtfSamples.isEmpty ? nil : rtfSamples.reduce(0, +) / Double(rtfSamples.count)
    }

    /// Replaces all pending work. The request in flight, if any, finishes and is stored.
    /// Returns true when this call will produce its own `.idle` (a new run loop started, or the
    /// immediate paused `.idle`), false when the plan was absorbed by a loop already running,
    /// whose `.idle` is already owed. Callers that wait for idleness count on this.
    @discardableResult
    public func setPlan(_ requests: [RenderRequest]) -> Bool {
        isCancelled = false
        if isPausedForStorage {
            continuation.yield(.idle)                              // never leave a waiter hanging while paused
            return true
        }
        pending = requests
        if !running {
            running = true
            Task { await self.run() }
            return true
        }
        return false
    }

    public func cancel() {
        isCancelled = true
        pending.removeAll()
    }

    public func resume() { isPausedForStorage = false }

    private func run() async {
        while !isPausedForStorage, !pending.isEmpty {
            await paceForegroundFillIfNeeded()
            guard !isPausedForStorage, !pending.isEmpty else { break }
            let batch = takeBatch()
            var paused = false
            for outcome in await render(batch) {
                switch outcome {
                case .events(let events):
                    events.forEach { continuation.yield($0) }
                case .storeFull:
                    guard !paused else { continue }               // one pause for the batch
                    paused = true
                    isPausedForStorage = true
                    pending.removeAll()
                    continuation.yield(.storeFull)
                }
            }
        }
        running = false
        continuation.yield(.idle)
    }

    /// Up to the engine's width for the first request's voice, from the front of `pending`, and
    /// never across a tier or a voice: an urgent plan then waits behind at most one batch of its own
    /// tier, and a hosted batch never shares a lease with an on-device one.
    /// On-device engines answer 1, so their batch is the single request it always was.
    private func takeBatch() -> [RenderRequest] {
        let first = pending.removeFirst()
        let width = max(1, engine.maxConcurrentRenders(for: first.voiceID))
        var batch = [first]
        while batch.count < width, let next = pending.first,
              next.job.tier == first.job.tier, next.voiceID == first.voiceID {
            batch.append(pending.removeFirst())
        }
        return batch
    }

    /// Rests between chapter-ahead calls. Quarter-second slices let a seek, an empty plan, or a new
    /// urgent play-ahead request preempt the rest promptly; the lease is not held while sleeping.
    private func paceForegroundFillIfNeeded() async {
        guard pending.first?.job.tier == .chapterAhead else {
            foregroundFillDelay = 0
            return
        }
        while foregroundFillDelay > 0, pending.first?.job.tier == .chapterAhead, !isCancelled {
            let slice = min(0.25, foregroundFillDelay)
            await foregroundFillSleeper(slice)
            foregroundFillDelay -= slice
        }
        foregroundFillDelay = 0
    }

    /// The lease is held once for the batch, at the tier of its first request, and scoped to the
    /// batch's cache checks, syntheses, and store writes. Preemption between tiers happens at
    /// batch boundaries; for a width of 1 that is the utterance boundary it always was.
    ///
    /// The budget sees the batch as one render: one wait for headroom before it, one measurement
    /// of the process's CPU across it. Charged per member, four hosted renders in flight each
    /// counted the other three and the player's own work as their cost, and a locked phone waited
    /// on a budget nothing had spent.
    private func render(_ batch: [RenderRequest]) async -> [RenderOutcome] {
        await arbiter.acquire(batch[0].job.tier)
        if isCancelled {
            await arbiter.release()
            return batch.map { _ in .events([]) }
        }
        var results = [RenderResult?](repeating: nil, count: batch.count)
        var uncached: [(index: Int, request: RenderRequest)] = []
        for (index, request) in batch.enumerated() {
            if let hit = await cachedResult(request) { results[index] = hit } else { uncached.append((index, request)) }
        }
        if !uncached.isEmpty {
            // In the background, only when the trailing window has room for what a batch costs: the
            // lease is held meanwhile, so the other tier waits behind this one rather than pile on.
            var waited: TimeInterval = 0
            if let budget {
                waited = await budget.waitForHeadroom(estimatedSeconds: lastRenderCPUSeconds ?? Self.firstRenderCPUEstimate)
            }
            let t0 = timeSource.now()
            let cpu0 = budget.map { _ in CPUBudget.processCPUSeconds() }
            if uncached.count == 1 {
                results[uncached[0].index] = await synthesizeAndStore(uncached[0].request)
            } else {
                await withTaskGroup(of: (Int, RenderResult).self) { group in
                    for (index, request) in uncached {
                        group.addTask { (index, await self.synthesizeAndStore(request)) }
                    }
                    for await (index, result) in group { results[index] = result }
                }
            }
            let wall = timeSource.now() - t0
            if let cpu0 { lastRenderCPUSeconds = max(0, CPUBudget.processCPUSeconds() - cpu0) }
            budget?.record()                                        // keeps the window's floor current
            // Throughput, not one render's latency: the rate control asks what the route can keep
            // fed, and four mirrors that each take ten seconds deliver forty seconds of audio in ten.
            // A failed member took wall time and made no audio: that batch says nothing.
            let synthesized = results.reduce(0) { $0 + ($1?.synthesizedSeconds ?? 0) }
            let failed = results.contains { $0?.failed == true }
            if synthesized > 0, !failed { record(rtf: wall / synthesized) }
            // The budget's report sink is the timing log's only view of what a render actually cost
            // and how long it waited to start — `CPUBudget`'s own pacing decisions live in `os_log`,
            // which the phone does not hand over either. Only worth a line once a wait was even
            // possible: in the foreground `waited` is always 0, so gate on the budget's state as the
            // batch finishes — a batch that started in front and finished after a lock still reports.
            if let budget, synthesized > 0, !budget.isForeground {
                budget.report?("render cpu \(String(format: "%.1f", lastRenderCPUSeconds ?? 0)) s for \(String(format: "%.1f", synthesized)) s of audio (rtf \(String(format: "%.2f", wall / synthesized))), waited \(String(format: "%.1f", waited)) s")
            }
        }
        await arbiter.release()
        return results.map { $0?.outcome ?? .events([]) }
    }

    /// The store already holds the key: reported as rendered, with the clip's duration and no word
    /// timings, and nothing is synthesized.
    private func cachedResult(_ request: RenderRequest) async -> RenderResult? {
        guard await store.contains(request.key), let clip = try? await store.read(request.key) else { return nil }
        foregroundFillDelay = 0
        return RenderResult(outcome: .events([.rendered(RenderedUtterance(
            documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex, key: request.key,
            duration: clip.duration, wordTimings: []))]), synthesizedSeconds: 0)
    }

    private func synthesizeAndStore(_ request: RenderRequest) async -> RenderResult {
        var events: [RenderEvent] = []
        var synthesized: TimeInterval = 0
        var failed = false
        let t0 = timeSource.now()
        var result: SynthesisResult
        do {
            result = request.stream
                ? try await streamed(request)
                : try await engine.synthesize(SynthesisRequest(spoken: request.spoken, voiceID: request.voiceID))
            let synthSeconds = timeSource.now() - t0
            if request.job.tier == .chapterAhead, let foregroundFillRate {
                foregroundFillDelay = max(0, result.audio.duration / foregroundFillRate - synthSeconds)
            } else {
                foregroundFillDelay = 0
            }
            synthesized = result.audio.duration
        } catch {
            foregroundFillDelay = 0
            failed = true
            events.append(.failed(documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex, message: "\(error)"))
            result = SynthesisResult(audio: .silence(seconds: Self.failureSilenceSeconds), wordTimings: [])
        }

        do {
            try await store.write(result.audio, for: request.key)
        } catch AudioStoreError.capacityExceeded, AudioStoreError.diskFull {
            return RenderResult(outcome: .storeFull, synthesizedSeconds: synthesized, failed: failed)
        } catch {
            // Encoding or I/O failed for this clip: log it and fall back to the failure silence so
            // the utterance still arrives (spec §6). Only if that write fails too is it bare failed.
            events.append(.failed(documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex, message: "\(error)"))
            result = SynthesisResult(audio: .silence(seconds: Self.failureSilenceSeconds), wordTimings: [])
            do {
                try await store.write(result.audio, for: request.key)
            } catch AudioStoreError.capacityExceeded, AudioStoreError.diskFull {
                return RenderResult(outcome: .storeFull, synthesizedSeconds: synthesized, failed: failed)
            } catch {
                return RenderResult(outcome: .events(events), synthesizedSeconds: synthesized, failed: failed)
            }
        }

        events.append(.rendered(RenderedUtterance(
            documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex, key: request.key,
            duration: result.audio.duration, wordTimings: result.wordTimings)))
        return RenderResult(outcome: .events(events), synthesizedSeconds: synthesized, failed: failed)
    }

    /// Renders in pieces, yielding each to the events stream the moment it arrives — the player is
    /// waiting on this utterance — and returns the whole for the store: the pieces' concatenation
    /// and the timings the engine folded over it.
    private func streamed(_ request: RenderRequest) async throws -> SynthesisResult {
        var pieces: [PCMAudio] = []
        var timings: [WordTiming] = []
        do {
            for try await chunk in engine.synthesizeStreaming(SynthesisRequest(spoken: request.spoken, voiceID: request.voiceID)) {
                switch chunk {
                case .piece(let audio, let ordinal, let isLast):
                    pieces.append(audio)
                    continuation.yield(.piece(documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex,
                                              audio: audio, ordinal: ordinal, isLast: isLast))
                case .finished(let wordTimings):
                    timings = wordTimings
                }
            }
        } catch {
            // Pieces already forwarded are in the player and were heard: the clip under the key must
            // be exactly those, not the failure silence, or the timeline's duration would disagree
            // with the audio for good. Nothing forwarded yet is an ordinary failure.
            guard !pieces.isEmpty else { throw error }
            continuation.yield(.failed(documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex, message: "\(error)"))
        }
        let sampleRate = pieces.first?.sampleRate ?? PCMAudio.defaultSampleRate
        return SynthesisResult(audio: PCMAudio(sampleRate: sampleRate, samples: pieces.flatMap(\.samples)), wordTimings: timings)
    }

    private func record(rtf: Double) {
        guard hasSkippedFirstSample else {
            hasSkippedFirstSample = true
            return
        }
        rtfSamples.append(rtf)
        if rtfSamples.count > rtfWindow { rtfSamples.removeFirst(rtfSamples.count - rtfWindow) }
    }

    private enum RenderOutcome: Sendable {
        case events([RenderEvent])
        case storeFull
    }

    private struct RenderResult: Sendable {
        var outcome: RenderOutcome
        /// Audio seconds this render actually synthesized: 0 for a cache hit or a failure, which
        /// therefore contribute nothing to the batch's RTF.
        var synthesizedSeconds: TimeInterval
        /// The synthesis threw: its wall time is not throughput, so the batch records no RTF.
        var failed = false
    }
}
