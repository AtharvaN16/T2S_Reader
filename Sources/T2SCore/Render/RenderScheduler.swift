import Foundation

public struct RenderRequest: Hashable, Sendable {
    public var job: RenderJob
    public var key: RenderKey
    public var spoken: String
    public var voiceID: String
    public init(job: RenderJob, key: RenderKey, spoken: String, voiceID: String) {
        self.job = job
        self.key = key
        self.spoken = spoken
        self.voiceID = voiceID
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
    case rendered(RenderedUtterance)
    /// Spec §6: logged; 200 ms of silence is stored under the key and a `.rendered` follows,
    /// unless storing the silence itself failed, in which case nothing follows.
    case failed(documentID: UUID, utteranceIndex: Int, message: String)
    /// Spec §6: the store refused the entry; rendering pauses until `resume()`.
    case storeFull
    /// The plan is empty (backpressure, spec §3.4).
    case idle
}

/// Serial executor of `RenderRequest`s (spec §3.4). Knows nothing about timelines: the
/// coordinator turns policy jobs into requests and applies the events.
public actor RenderScheduler {
    public static let failureSilenceSeconds: TimeInterval = 0.2

    public nonisolated let events: AsyncStream<RenderEvent>
    private let continuation: AsyncStream<RenderEvent>.Continuation
    private let engine: any SynthesisEngine
    private let store: any AudioStore
    private let timeSource: any TimeSource
    private let rtfWindow: Int

    public private(set) var pending: [RenderRequest] = []
    public private(set) var isPausedForStorage = false
    private var running = false
    private var rtfSamples: [Double] = []

    public init(engine: any SynthesisEngine, store: any AudioStore, timeSource: any TimeSource, rtfWindow: Int = 20) {
        self.engine = engine
        self.store = store
        self.timeSource = timeSource
        self.rtfWindow = max(1, rtfWindow)
        (events, continuation) = AsyncStream.makeStream(of: RenderEvent.self, bufferingPolicy: .unbounded)
    }

    /// Rolling mean of synth seconds per audio second over the last `rtfWindow` renders.
    public var measuredRTF: Double? {
        rtfSamples.isEmpty ? nil : rtfSamples.reduce(0, +) / Double(rtfSamples.count)
    }

    /// Replaces all pending work. The request in flight, if any, finishes and is stored.
    /// Returns true when this call will produce its own `.idle` (a new run loop started, or the
    /// immediate paused `.idle`), false when the plan was absorbed by a loop already running,
    /// whose `.idle` is already owed. Callers that wait for idleness count on this.
    @discardableResult
    public func setPlan(_ requests: [RenderRequest]) -> Bool {
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

    public func cancel() { pending.removeAll() }

    public func resume() { isPausedForStorage = false }

    private func run() async {
        while !isPausedForStorage, !pending.isEmpty {
            let request = pending.removeFirst()
            if await store.contains(request.key) { continue }
            let t0 = timeSource.now()
            var result: SynthesisResult
            do {
                result = try await engine.synthesize(SynthesisRequest(spoken: request.spoken, voiceID: request.voiceID))
                let synthSeconds = timeSource.now() - t0
                if result.audio.duration > 0 { record(rtf: synthSeconds / result.audio.duration) }
            } catch {
                continuation.yield(.failed(documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex, message: "\(error)"))
                result = SynthesisResult(audio: .silence(seconds: Self.failureSilenceSeconds), wordTimings: [])
            }
            do {
                try await store.write(result.audio, for: request.key)
            } catch AudioStoreError.capacityExceeded {
                isPausedForStorage = true
                pending.removeAll()
                continuation.yield(.storeFull)
                break
            } catch {
                // Encoding or I/O failed for this clip: log it and fall back to the failure silence
                // so the utterance still arrives (spec §6). Only if that write fails too does a
                // bare `.failed` go out with no `.rendered` behind it.
                continuation.yield(.failed(documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex, message: "\(error)"))
                result = SynthesisResult(audio: .silence(seconds: Self.failureSilenceSeconds), wordTimings: [])
                do {
                    try await store.write(result.audio, for: request.key)
                } catch {
                    continue
                }
            }
            continuation.yield(.rendered(RenderedUtterance(
                documentID: request.job.documentID, utteranceIndex: request.job.utteranceIndex, key: request.key,
                duration: result.audio.duration, wordTimings: result.wordTimings)))
        }
        running = false
        continuation.yield(.idle)
    }

    private func record(rtf: Double) {
        rtfSamples.append(rtf)
        if rtfSamples.count > rtfWindow { rtfSamples.removeFirst(rtfSamples.count - rtfWindow) }
    }
}
