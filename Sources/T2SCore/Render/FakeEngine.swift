import Foundation

/// Silence of a precisely known duration with synthetic word timings (spec §8).
public actor FakeEngine: SynthesisEngine {
    public nonisolated let engineID = "fake"
    public let secondsPerCharacter: TimeInterval
    /// When set, each call advances `timeSource` by `simulatedRTF × audio seconds`.
    public let simulatedRTF: Double?
    private let timeSource: ManualTimeSource?
    private var failures: Set<String> = []
    private var held = false
    private var parked: [CheckedContinuation<Void, Never>] = []
    public private(set) var requests: [SynthesisRequest] = []

    public init(secondsPerCharacter: TimeInterval = 0.05, simulatedRTF: Double? = nil, timeSource: ManualTimeSource? = nil) {
        self.secondsPerCharacter = secondsPerCharacter
        self.simulatedRTF = simulatedRTF
        self.timeSource = timeSource
    }

    public func fail(on spoken: String) { failures.insert(spoken) }

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

    private static let word = Pattern("\\S+")
}
