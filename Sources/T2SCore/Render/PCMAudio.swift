import Foundation

/// Mono PCM. The engine's native output; encoded before it is ever persisted (spec §3.4).
public struct PCMAudio: Hashable, Sendable {
    public static let defaultSampleRate: Double = 24_000
    public var sampleRate: Double
    public var samples: [Float]

    public init(sampleRate: Double = PCMAudio.defaultSampleRate, samples: [Float]) {
        self.sampleRate = sampleRate
        self.samples = samples
    }

    public var duration: TimeInterval { Double(samples.count) / sampleRate }

    public static func silence(seconds: TimeInterval, sampleRate: Double = PCMAudio.defaultSampleRate) -> PCMAudio {
        PCMAudio(sampleRate: sampleRate, samples: Array(repeating: 0, count: Int((seconds * sampleRate).rounded())))
    }
}
