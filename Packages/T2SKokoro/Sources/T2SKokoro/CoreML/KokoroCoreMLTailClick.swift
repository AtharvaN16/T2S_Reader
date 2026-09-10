import Foundation
import KokoroPipeline

/// Removes the click the Core ML pipeline leaves at the tail of every call.
///
/// Measured in `spikes/findings/2026-09-08-ticks-and-hyphens.md` and, across all 28 voices, in the
/// 2026-09-10 section of the same finding (`scripts/voice-tail-probe.sh`): the trimmed audio of every
/// call ends in 36–45 ms of digital silence — the generator's output for the bucket's zero padding,
/// which its ~40 ms look-ahead pulls inside the kept audio — and just before that silence sits a
/// burst of 5–30 ms, its energy in the 10 ms before the zeros, at up to −5 dBFS: the generator's
/// pre-echo of the step from real features into the padding. Its *place* is fixed by the pipeline —
/// it began no more than 66 ms before the end in 44 clean cases over 28 voices — while its
/// *surroundings* are the voice's: on Heart it is an island between two runs of exact zeros, on
/// Alloy a floor of −60 dBFS noise laps at it, on Jessica it rides on the last word's slow decay
/// with no gap at all. The first cut of this rule looked for the island shape and so removed the
/// burst from six voices and left it on twenty-two (the owner, 2026-09-10: changing voice brought
/// the clicks back). The MLX reference never produces it.
///
/// So ``removed(from:)`` goes by place, not shape: the last ``zeroedSamples`` are set to zero and the
/// ``fadeSamples`` before them ramp down to meet it, on every call. What that window holds besides
/// the burst is the end-of-input pause — the EOS token's single 25 ms frame, shifted by the same
/// look-ahead — and at most the last few milliseconds of the final token's decay, which the fade
/// takes down rather than cuts. The seam trim (`KokoroCoreMLSeam`) then measures the tail as the
/// silence it now is.
enum KokoroCoreMLTailClick {
    /// The tail set to zero: 70 ms, the measured 66 ms plus a margin for the zeros' own ±5 ms scatter.
    static let zeroedSamples = PipelineConstants.sampleRate * 70 / 1000
    /// The ramp down into the zeros, so audio reaching the window steps down without a click.
    static let fadeSamples = PipelineConstants.sampleRate * 10 / 1000
    /// A call shorter than this is left alone: no real piece is — BOS lead-in, one token and EOS are
    /// hundreds of milliseconds — and zeroing most of a synthetic one would be wrong.
    static let minimumSamples = PipelineConstants.sampleRate * 120 / 1000

    /// `samples` with the tail window zeroed and the ramp before it applied, or `samples` unchanged
    /// when they are shorter than ``minimumSamples``.
    static func removed(from samples: [Float]) -> [Float] {
        let count = samples.count
        guard count > minimumSamples else { return samples }
        var cleaned = samples
        let zeroFrom = count - zeroedSamples
        for k in zeroFrom ..< count { cleaned[k] = 0 }
        let fadeFrom = zeroFrom - fadeSamples
        for k in fadeFrom ..< zeroFrom {
            // 1 at the ramp's first sample, falling towards 0 at the zeros.
            cleaned[k] *= Float(zeroFrom - k) / Float(fadeSamples + 1)
        }
        return cleaned
    }
}
