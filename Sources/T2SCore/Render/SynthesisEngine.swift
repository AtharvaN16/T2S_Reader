import Foundation

public struct SynthesisRequest: Hashable, Sendable {
    public var spoken: String
    public var voiceID: String
    public init(spoken: String, voiceID: String) {
        self.spoken = spoken
        self.voiceID = voiceID
    }
}

public struct SynthesisResult: Hashable, Sendable {
    public var audio: PCMAudio
    /// Offsets into `spoken`; times relative to the utterance start at 1x.
    public var wordTimings: [WordTiming]
    public init(audio: PCMAudio, wordTimings: [WordTiming]) {
        self.audio = audio
        self.wordTimings = wordTimings
    }
}

public enum SynthesisError: Error, Equatable, Sendable {
    case failed(String)
}

/// One step of a streamed render (Plan 14). Pieces arrive in order as the engine finishes them and
/// concatenate to exactly the audio `synthesize` would have returned; `.finished` follows the last
/// piece with the word timings over that concatenation.
public enum SynthesisChunk: Sendable, Hashable {
    case piece(PCMAudio, ordinal: Int, isLast: Bool)
    case finished(wordTimings: [WordTiming])
}

/// One implementation per backend (spec §3): Kokoro on-device, HTTP for BYO keys, Fake for tests.
public protocol SynthesisEngine: Sendable {
    /// Part of every render key (spec §5); change it when output would differ.
    var engineID: String { get }
    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult

    /// Renders `request` in pieces, yielding each as it completes, then `.finished`. The head
    /// utterance the player is waiting on is rendered this way so the first sound needs one short
    /// piece, not the whole utterance (audit §3.1). Engines that cannot stream yield the whole
    /// render as one piece — the default below.
    func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error>

    /// How many renders the scheduler may hold in flight at once for `voiceID`'s route. Every
    /// engine that renders on the device answers 1; a hosted route answers with its mirror count.
    func maxConcurrentRenders(for voiceID: String) -> Int
}

public extension SynthesisEngine {
    func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await synthesize(request)
                    continuation.yield(.piece(result.audio, ordinal: 0, isLast: true))
                    continuation.yield(.finished(wordTimings: result.wordTimings))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func maxConcurrentRenders(for voiceID: String) -> Int { 1 }
}
