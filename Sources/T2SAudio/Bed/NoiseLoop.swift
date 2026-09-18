import Foundation
import T2SCore

public enum NoiseColour: String, Hashable, Sendable, CaseIterable {
    case brown, pink
}

/// Noise made in code, as a loop the bed can play like a recording (soundscape design §3, option
/// 3): thirty seconds of it is indistinguishable from endless, and it weighs nothing in the bundle.
/// Not normalised here — `Loudness` does that for every bed alike.
public enum NoiseLoop {
    public static func make(_ colour: NoiseColour, seconds: TimeInterval = 30, sampleRate: Double = 48_000,
                            seed: UInt64 = 0x5EED) -> PCMAudio {
        let n = Int((seconds * sampleRate).rounded())
        var generator = SplitMix64(seed: seed)
        var out = [Float](repeating: 0, count: n)
        switch colour {
        case .brown:
            // A leaky integrator over white noise: −6 dB per octave, the deep, even wash.
            var level: Float = 0
            for i in 0..<n {
                level = 0.995 * level + 0.02 * generator.nextFloat()
                out[i] = level
            }
        case .pink:
            // Kellet's economy filter: three one-pole stages summed, −3 dB per octave.
            var b0: Float = 0, b1: Float = 0, b2: Float = 0
            for i in 0..<n {
                let white = generator.nextFloat()
                b0 = 0.99765 * b0 + white * 0.0990460
                b1 = 0.96300 * b1 + white * 0.2965164
                b2 = 0.57000 * b2 + white * 1.0526913
                out[i] = (b0 + b1 + b2 + white * 0.1848) * 0.05
            }
        }
        return PCMAudio(sampleRate: sampleRate, samples: out)
    }
}

/// A tiny deterministic generator: the same seed gives the same noise on every device, every run.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in −1…1.
    mutating func nextFloat() -> Float {
        Float(Double(next() >> 11) / Double(1 << 52)) - 1
    }
}
