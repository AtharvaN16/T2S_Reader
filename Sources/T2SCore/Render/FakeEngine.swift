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
    /// A `releasePiece()` that arrives before anything has parked yet would otherwise be a lost
    /// wakeup; it banks a credit here instead, which the next `waitBetweenPieces()` call consumes
    /// rather than parking.
    private var pieceReleases = 0
    public private(set) var requests: [SynthesisRequest] = []

    public init(secondsPerCharacter: TimeInterval = 0.05, simulatedRTF: Double? = nil, timeSource: ManualTimeSource? = nil, pieceCount: Int = 1) {
        self.secondsPerCharacter = secondsPerCharacter
        self.simulatedRTF = simulatedRTF
        self.timeSource = timeSource
        self.pieceCount = pieceCount
    }

    public func fail(on spoken: String) { failures.insert(spoken) }

    /// The streamed render throws after yielding piece `ordinal` (a mid-stream engine failure) — once
    /// it is released from any hold between pieces, so a test can fail an engine that is parked.
    public func fail(afterPiece ordinal: Int) { failAfterPiece = ordinal }
    private var failAfterPiece: Int?

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

    /// Releases exactly one parked piece — or, if none is parked yet, banks a credit so the next
    /// piece to reach `waitBetweenPieces()` finds itself already released instead of parking. Without
    /// the credit, a `releasePiece()` that wins the race against the piece actually parking would be a
    /// lost wakeup, hanging the stream forever.
    public func releasePiece() {
        if let next = pieceWaiters.first {
            pieceWaiters.removeFirst()
            next.resume()
        } else {
            pieceReleases += 1
        }
    }

    /// How many pieces are currently parked between pieces — lets a test confirm a piece has actually
    /// reached the park point (rather than racing `releasePiece()` against it) or drained back to zero
    /// after a cancellation.
    public var parkedPieceCount: Int { pieceWaiters.count }

    /// Lets the rest of the pieces flow without parking again, for a test that only cares about
    /// the first hold. Resumes everyone currently parked directly, rather than through
    /// `releasePiece()`, which now only ever resumes one.
    public func stopHoldingBetweenPieces() {
        holdingBetweenPieces = false
        let waiting = pieceWaiters
        pieceWaiters.removeAll()
        waiting.forEach { $0.resume() }
    }

    /// The whole render, cut into `pieceCount` near-equal pieces of whole samples — the last takes
    /// the remainder — so the pieces concatenate to exactly `synthesize`'s audio. Clamped to the
    /// sample count so no piece is empty unless the whole render is.
    public nonisolated func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let whole = try await self.synthesize(request)
                    let samples = whole.audio.samples
                    let count = max(1, min(self.pieceCount, max(1, samples.count)))
                    let size = samples.count / count
                    for ordinal in 0 ..< count {
                        if ordinal > 0 {
                            await self.waitBetweenPieces()
                            try await self.failIfAsked(afterPiece: ordinal - 1)
                        }
                        try Task.checkCancellation()
                        let start = ordinal * size
                        let end = ordinal == count - 1 ? samples.count : start + size
                        continuation.yield(.piece(PCMAudio(sampleRate: whole.audio.sampleRate, samples: Array(samples[start ..< end])),
                                                  ordinal: ordinal, isLast: ordinal == count - 1))
                    }
                    try await self.failIfAsked(afterPiece: count - 1)
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
    //
    // Cancellation-aware (Task 2 review, finding 1): `withCheckedContinuation` alone is not
    // cancellation-aware, so a consumer that stops iterating early — e.g. takes piece 0 and breaks
    // out of the `for try await` — cancels this task (via `continuation.onTermination`) while it may
    // be parked here, and nothing would otherwise ever resume it. `Task.isCancelled` is checked before
    // parking so an already-cancelled task never parks at all, and `withTaskCancellationHandler` wraps
    // the park so a *mid-park* cancellation also resumes it (from `resumeParkedPieces()`, hopping back
    // onto the actor since `onCancel` itself runs outside actor isolation) — the resumed call then
    // returns here, and the caller's `try Task.checkCancellation()` throws and ends the stream.
    private func failIfAsked(afterPiece ordinal: Int) throws {
        if let failAfterPiece, ordinal == failAfterPiece { throw SynthesisError.failed("failed after piece \(ordinal)") }
    }

    private func waitBetweenPieces() async {
        if Task.isCancelled { return }
        guard holdingBetweenPieces else { return }
        if pieceReleases > 0 {
            pieceReleases -= 1
            return
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                pieceWaiters.append(continuation)
            }
        } onCancel: {
            Task { await self.resumeParkedPieces() }
        }
    }

    /// Resumes every currently parked piece without touching `holdingBetweenPieces` — the cancellation
    /// path for `waitBetweenPieces()`, called from its `onCancel` handler.
    private func resumeParkedPieces() {
        let waiting = pieceWaiters
        pieceWaiters.removeAll()
        waiting.forEach { $0.resume() }
    }

    private static let word = Pattern("\\S+")
}
