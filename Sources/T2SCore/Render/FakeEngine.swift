import Foundation

/// Silence of a precisely known duration with synthetic word timings (spec §8).
public actor FakeEngine: SynthesisEngine {
    public nonisolated let engineID = "fake"
    public let secondsPerCharacter: TimeInterval
    /// The whole render is cut into this many pieces when streamed. 1 by default, so a plain
    /// `FakeEngine` streams the way the protocol's default extension would.
    public let pieceCount: Int
    /// When set, each call advances `timeSource` by `simulatedRTF × audio seconds`.
    public private(set) var simulatedRTF: Double?
    private let timeSource: ManualTimeSource?
    private var failures: Set<String> = []
    private var held = false
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var holdingBetweenPieces = false
    private var pieceWaiters: [CheckedContinuation<Void, Never>] = []
    public private(set) var requests: [SynthesisRequest] = []

    public init(secondsPerCharacter: TimeInterval = 0.05, simulatedRTF: Double? = nil, timeSource: ManualTimeSource? = nil, pieceCount: Int = 1) {
        self.secondsPerCharacter = secondsPerCharacter
        self.simulatedRTF = simulatedRTF
        self.timeSource = timeSource
        self.pieceCount = pieceCount
    }

    public func fail(on spoken: String) { failures.insert(spoken) }

    /// Changes the simulated machine mid-run: a phone that was throttling and is not any more, or
    /// the other way about.
    public func setSimulatedRTF(_ rtf: Double?) { simulatedRTF = rtf }

    /// Every later `synthesize` parks until `release()`.
    public func hold() { held = true }

    public func release() {
        held = false
        let waiting = parked
        parked.removeAll()
        waiting.forEach { $0.resume() }
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        while held { await withCheckedContinuation { parked.append($0) } }
        requests.append(request)
        if failures.contains(request.spoken) { throw SynthesisError.failed(request.spoken) }
        let rate = PCMAudio.defaultSampleRate
        let sampleCount = Int((Double(request.spoken.utf16.count) * secondsPerCharacter * rate).rounded())
        let seconds = Double(sampleCount) / rate                     // exact: what the audio really lasts
        if let rtf = simulatedRTF { timeSource?.advance(by: rtf * seconds) }
        let audio = PCMAudio(sampleRate: rate, samples: Array(repeating: 0, count: sampleCount))
        let n = max(1, request.spoken.utf16.count)
        let ns = request.spoken as NSString
        let words = Self.word.regex.matches(in: request.spoken, range: NSRange(location: 0, length: ns.length))
        let timings = words.map { m -> WordTiming in
            let r = m.range.location..<(m.range.location + m.range.length)
            return WordTiming(spokenRange: r,
                              start: seconds * Double(r.lowerBound) / Double(n),
                              end: seconds * Double(r.upperBound) / Double(n))
        }
        return SynthesisResult(audio: audio, wordTimings: timings)
    }

    /// Every piece after the first parks until `releasePiece()`, so a test can watch what happens
    /// between the first sound and the rest.
    public func holdBetweenPieces() { holdingBetweenPieces = true }

    public func releasePiece() {
        let waiting = pieceWaiters
        pieceWaiters.removeAll()
        waiting.forEach { $0.resume() }
    }

    /// Lets the rest of the pieces flow without parking again, for a test that only cares about
    /// the first hold.
    public func stopHoldingBetweenPieces() { holdingBetweenPieces = false; releasePiece() }

    /// The whole render, cut into `pieceCount` near-equal pieces of whole samples — the last takes
    /// the remainder — so the pieces concatenate to exactly `synthesize`'s audio.
    public nonisolated func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let whole = try await self.synthesize(request)
                    let count = max(1, await self.pieceCount)
                    let samples = whole.audio.samples
                    let size = samples.count / count
                    for ordinal in 0 ..< count {
                        if ordinal > 0 { await self.waitBetweenPieces() }
                        try Task.checkCancellation()
                        let start = ordinal * size
                        let end = ordinal == count - 1 ? samples.count : start + size
                        continuation.yield(.piece(PCMAudio(sampleRate: whole.audio.sampleRate, samples: Array(samples[start ..< end])),
                                                  ordinal: ordinal, isLast: ordinal == count - 1))
                    }
                    continuation.yield(.finished(wordTimings: whole.wordTimings))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // Parks at most once per call: `releasePiece()` resumes whatever is parked for *this* piece and
    // returns, rather than re-checking the flag and parking again for the same piece — the flag
    // staying set is what makes the *next* piece's call park in turn (`while` here would re-park
    // the same piece forever after a single `releasePiece()`, since nothing ever clears the flag).
    private func waitBetweenPieces() async {
        if holdingBetweenPieces { await withCheckedContinuation { pieceWaiters.append($0) } }
    }

    private static let word = Pattern("\\S+")
}
