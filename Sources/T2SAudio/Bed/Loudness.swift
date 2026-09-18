import Foundation
import T2SCore

/// Every bed at the same loudness (soundscape design §2.4): scaled to a target RMS under a peak
/// ceiling, so the one Volume slider means the same for Rain as for Fire — or for noise.
public enum Loudness {
    public static func normalised(_ audio: PCMAudio, toRMSDecibels target: Float = -20,
                                  peakCeilingDecibels ceiling: Float = -1) -> PCMAudio {
        let samples = audio.samples
        guard !samples.isEmpty else { return audio }
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        let peak = samples.reduce(0) { max($0, abs($1)) }
        guard rms > 0, peak > 0 else { return audio }
        var gain = linear(target) / rms
        let ceilingLinear = linear(ceiling)
        if peak * gain > ceilingLinear { gain = ceilingLinear / peak }        // the ceiling wins
        return PCMAudio(sampleRate: audio.sampleRate, samples: samples.map { $0 * gain })
    }

    public static func linear(_ decibels: Float) -> Float { powf(10, decibels / 20) }

    public static func decibels(_ linear: Float) -> Float { 20 * log10f(max(linear, 1e-9)) }
}
