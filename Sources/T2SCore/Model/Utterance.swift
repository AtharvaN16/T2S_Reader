import Foundation

public struct SpanMap: Codable, Hashable, Sendable {
    public var sourceRange: Range<Int>
    public var spokenRange: Range<Int>

    public init(sourceRange: Range<Int>, spokenRange: Range<Int>) {
        self.sourceRange = sourceRange
        self.spokenRange = spokenRange
    }

    /// A linear span maps character-for-character and may be sliced. Anything else is atomic.
    /// Equal length is a heuristic: a same-length replacement is treated as linear, which is
    /// harmless because projection unions whole words anyway.
    public var isLinear: Bool { sourceRange.count == spokenRange.count }
}

public struct WordTiming: Codable, Hashable, Sendable {
    public var spokenRange: Range<Int>
    public var start: TimeInterval
    public var end: TimeInterval

    public init(spokenRange: Range<Int>, start: TimeInterval, end: TimeInterval) {
        self.spokenRange = spokenRange
        self.start = start
        self.end = end
    }
}

/// Always at 1x (spec §3.1).
public enum UtteranceDuration: Codable, Hashable, Sendable {
    case estimated(TimeInterval)
    case actual(TimeInterval)

    public var seconds: TimeInterval {
        switch self {
        case .estimated(let s), .actual(let s): return s
        }
    }

    public var isActual: Bool {
        if case .actual = self { return true }
        return false
    }
}

public struct Utterance: Codable, Hashable, Sendable {
    public var position: Position
    public var source: String
    public var spoken: String
    public var spans: [SpanMap]
    /// Render key of the cached audio file (spec §5), nil until rendered.
    public var audioRef: String?
    public var duration: UtteranceDuration
    public var wordTimings: [WordTiming]?

    public init(position: Position, source: String, spoken: String, spans: [SpanMap],
                audioRef: String? = nil, duration: UtteranceDuration, wordTimings: [WordTiming]? = nil) {
        self.position = position
        self.source = source
        self.spoken = spoken
        self.spans = spans
        self.audioRef = audioRef
        self.duration = duration
        self.wordTimings = wordTimings
    }
}
