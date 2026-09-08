import Foundation
import KokoroPipeline

/// Removes the click the Core ML pipeline leaves at the tail of every call.
///
/// Measured in `spikes/findings/2026-09-08-ticks-and-hyphens.md`: the trimmed audio of every call ends
/// in about 40 ms of digital silence, and just before it — 60 to 40 ms from the end — sits a burst of
/// about 20 ms bounded by silence on both sides, at −12 to −15 dBFS when speech ended shortly before the
/// call did (after a comma, a closing quote or a bare word at a piece cut) and inaudible when the call
/// ends in a long predicted pause. The MLX reference never produces it. The reader hears it as a tick
/// before the sentence resumes wherever a call ends inside a sentence, and as a mouth noise before every
/// new sentence.
///
/// The shape is unique — speech never ends in a short island between two runs of silence — so
/// ``removed(from:)`` zeroes exactly that and nothing else. Silence is anything under −80 dBFS, in case
/// a phone's fp16 stages leave a floor where this Mac leaves exact zeros.
enum KokoroCoreMLTailClick {
    /// Below this magnitude a sample is silence: −80 dBFS.
    static let silence: Float = 1e-4
    /// The island must lie entirely within this much of the end.
    static let windowSamples = PipelineConstants.sampleRate * 120 / 1000
    /// The longest island that is the artifact rather than a short word.
    static let maxIslandSamples = PipelineConstants.sampleRate * 30 / 1000
    /// The silence required after the island (through to the end) and before it.
    static let minSilenceSamples = PipelineConstants.sampleRate * 10 / 1000

    /// `samples` with the tail island zeroed, or `samples` unchanged when the tail has no island.
    static func removed(from samples: [Float]) -> [Float] {
        let count = samples.count
        guard count > windowSamples else { return samples }
        func isSilent(_ index: Int) -> Bool { abs(samples[index]) < silence }

        // The trailing silence, which must be at least `minSilenceSamples` long.
        var islandEnd = count
        while islandEnd > 0, isSilent(islandEnd - 1) { islandEnd -= 1 }
        guard count - islandEnd >= minSilenceSamples, islandEnd > 0 else { return samples }

        // Back over the island until a run of silence at least `minSilenceSamples` long precedes it.
        // Zero crossings inside the island dip under the threshold for a sample or two; only a run of
        // silence long enough to be a pause counts as the island's start.
        var index = islandEnd
        var silentRun = 0
        var islandStart: Int?
        while index > 0, islandEnd - index <= maxIslandSamples + minSilenceSamples {
            index -= 1
            if isSilent(index) {
                silentRun += 1
                if silentRun >= minSilenceSamples {
                    islandStart = index + minSilenceSamples
                    break
                }
            } else {
                silentRun = 0
            }
        }
        guard let start = islandStart, islandEnd - start <= maxIslandSamples, count - start <= windowSamples else {
            return samples
        }
        var cleaned = samples
        for k in start ..< islandEnd { cleaned[k] = 0 }
        return cleaned
    }
}
