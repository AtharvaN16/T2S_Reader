import Foundation
import Testing
@testable import T2SKokoro

/// The Core ML pipeline leaves a click at the tail of every call: a burst of 5–30 ms just before the
/// 36–45 ms of digital silence every call ends in, at up to −5 dBFS. Its place is the pipeline's and
/// the same for every voice; what surrounds it — exact zeros on Heart, a noise floor on Alloy, the
/// last word's decay on Jessica — is the voice's, which is why the first rule (an island between two
/// runs of silence) removed it from six voices of 28. `spikes/findings/2026-09-08-ticks-and-hyphens.md`
/// measured both; ``KokoroCoreMLTailClick`` zeroes the place, fading into it.
@Suite struct KokoroCoreMLTailClickTests {
    static let rate = 24_000

    /// A 220 Hz tone at `amplitude` for `ms` milliseconds.
    static func tone(ms: Int, amplitude: Float = 0.3) -> [Float] {
        (0 ..< rate * ms / 1000).map { amplitude * sin(Float($0) * 2 * .pi * 220 / Float(rate)) }
    }
    static func silence(ms: Int, floor: Float = 0) -> [Float] {
        (0 ..< rate * ms / 1000).map { floor * (($0 % 2 == 0) ? 1 : -1) }
    }
    /// A call's tail as the pipeline leaves it: the burst, then the zeros.
    static func burstAndZeros(burstMs: Int = 20, zerosMs: Int = 40, amplitude: Float = 0.5) -> [Float] {
        tone(ms: burstMs, amplitude: amplitude) + silence(ms: zerosMs)
    }

    /// Heart's shape: the burst is an island between two runs of exact zeros.
    @Test func zeroesTheBurstBeforeTheFinalZeros() {
        let speech = Self.tone(ms: 1000)
        let samples = speech + Self.silence(ms: 100) + Self.burstAndZeros()
        let cleaned = KokoroCoreMLTailClick.removed(from: samples)
        #expect(cleaned.count == samples.count)
        #expect(Array(cleaned.prefix(speech.count)) == speech)
        #expect(cleaned.suffix(samples.count - speech.count).allSatisfy { $0 == 0 })
    }

    /// Alloy's shape: a noise floor laps at the burst, and the burst starts earlier and ends later
    /// than Heart's — 66 ms before the end was the earliest start measured, 36 ms the shortest zeros.
    @Test func zeroesABurstInANoiseFloorAtTheEdgesOfItsWindow() {
        let speech = Self.tone(ms: 1000)
        let samples = speech + Self.silence(ms: 100, floor: 1e-3) + Self.burstAndZeros(burstMs: 30, zerosMs: 36)
        let cleaned = KokoroCoreMLTailClick.removed(from: samples)
        #expect(cleaned.suffix(KokoroCoreMLTailClick.zeroedSamples).allSatisfy { $0 == 0 })
        #expect(Array(cleaned.prefix(speech.count)) == speech)
    }

    /// Jessica's shape: the last word decays straight into the burst with no gap. The burst goes,
    /// the decay steps down through the ramp rather than off a cliff.
    @Test func zeroesABurstRidingOnTheLastWordsDecay() {
        let speech = Self.tone(ms: 1000)
        let decay = (0 ..< Self.rate * 60 / 1000).map { k -> Float in
            0.05 * (1 - Float(k) / Float(Self.rate * 60 / 1000)) * sin(Float(k) * 2 * .pi * 220 / Float(Self.rate))
        }
        let samples = speech + decay + Self.burstAndZeros()
        let cleaned = KokoroCoreMLTailClick.removed(from: samples)
        #expect(cleaned.suffix(KokoroCoreMLTailClick.zeroedSamples).allSatisfy { $0 == 0 })
        #expect(Array(cleaned.prefix(speech.count)) == speech)
        let largestStep = zip(cleaned.dropFirst(), cleaned).map { abs($0 - $1) }.max() ?? 0
        let toneStep = zip(speech.dropFirst(), speech).map { abs($0 - $1) }.max() ?? 0
        #expect(largestStep <= toneStep, "the ramp must not add a step the tone itself does not have")
    }

    /// Audio reaching the window is ramped down over `fadeSamples`, not cut: the ramp's first sample
    /// keeps the audio, its last is nearly gone, and the window after it is zero.
    @Test func fadesIntoTheWindowRatherThanCuttingAtIt() {
        let samples = Self.tone(ms: 1000, amplitude: 1)
        let cleaned = KokoroCoreMLTailClick.removed(from: samples)
        let zeroFrom = samples.count - KokoroCoreMLTailClick.zeroedSamples
        let fadeFrom = zeroFrom - KokoroCoreMLTailClick.fadeSamples
        #expect(Array(cleaned.prefix(fadeFrom)) == Array(samples.prefix(fadeFrom)))
        #expect(cleaned.suffix(KokoroCoreMLTailClick.zeroedSamples).allSatisfy { $0 == 0 })
        for k in fadeFrom ..< zeroFrom where samples[k] != 0 {
            let gain = cleaned[k] / samples[k]
            let expected = Float(zeroFrom - k) / Float(KokoroCoreMLTailClick.fadeSamples + 1)
            #expect(abs(gain - expected) < 1e-5)
        }
    }

    /// Only the tail is examined: an island in the middle of the audio is left for the ear.
    @Test func leavesAnIslandFarFromTheEnd() {
        let samples = Self.tone(ms: 500) + Self.silence(ms: 20) + Self.tone(ms: 20, amplitude: 0.2) + Self.silence(ms: 20)
            + Self.tone(ms: 500) + Self.silence(ms: 100)
        let cleaned = KokoroCoreMLTailClick.removed(from: samples)
        let untouched = samples.count - KokoroCoreMLTailClick.zeroedSamples - KokoroCoreMLTailClick.fadeSamples
        #expect(Array(cleaned.prefix(untouched)) == Array(samples.prefix(untouched)))
    }

    /// A tail that is already silent stays as it is: nothing to fade, nothing to zero.
    @Test func leavesAnAllSilentTail() {
        let samples = Self.tone(ms: 1000) + Self.silence(ms: 200)
        #expect(KokoroCoreMLTailClick.removed(from: samples) == samples)
    }

    @Test func leavesAudioShorterThanTheMinimum() {
        let samples = Self.tone(ms: 100)
        #expect(KokoroCoreMLTailClick.removed(from: samples) == samples)
        #expect(KokoroCoreMLTailClick.removed(from: []) == [])
    }
}
