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

/// One implementation per backend (spec §3): Kokoro on-device, HTTP for BYO keys, Fake for tests.
public protocol SynthesisEngine: Sendable {
    /// Part of every render key (spec §5); change it when output would differ.
    var engineID: String { get }
    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult
}
