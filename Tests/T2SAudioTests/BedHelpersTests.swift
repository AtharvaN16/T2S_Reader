import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@Suite struct BedHelpersTests {
    /// Deterministic "noise": a fixed pseudo-random sequence, so a seam test is the same every run.
    private func noise(_ count: Int, rate: Double = 1000) -> PCMAudio {
        var g = SplitMix64(seed: 42)
        return PCMAudio(sampleRate: rate, samples: (0..<count).map { _ in g.nextFloat() * 0.5 })
    }

    private func rms(_ s: ArraySlice<Float>) -> Float {
        sqrt(s.reduce(0) { $0 + $1 * $1 } / Float(max(1, s.count)))
    }

    @Test func theSeamDropsTheTailAndStaysContinuousAtTheWrap() {
        let audio = noise(1000)                                            // 1 s at 1 kHz
        let seamed = LoopSeam.bake(audio, crossfadeSeconds: 0.2)          // 200 samples crossfaded
        #expect(seamed.samples.count == 800)
        #expect(seamed.sampleRate == 1000)
        // The first output sample is the tail's first sample at full gain: what was playing at the
        // wrap carries straight on.
        #expect(abs(seamed.samples[0] - audio.samples[800]) < 1e-5)
        // Past the crossfade the loop is the original again.
        #expect(seamed.samples[300] == audio.samples[300])
    }

    @Test func theSeamKeepsTheLoudnessOfNoise() {
        let seamed = LoopSeam.bake(noise(4000), crossfadeSeconds: 1)      // 1000-sample seam
        let inSeam = rms(seamed.samples[0..<1000])
        let outside = rms(seamed.samples[1000..<3000])
        #expect(abs(Loudness.decibels(inSeam) - Loudness.decibels(outside)) < 1)   // within 1 dB
    }

    @Test func aLoopTooShortToSeamIsLeftAlone() {
        let short = noise(300)
        #expect(LoopSeam.bake(short, crossfadeSeconds: 0.2) == short)    // needs 400 samples
    }

    @Test func noiseIsDeterministicFiniteAndColoured() {
        let brown = NoiseLoop.make(.brown, seconds: 0.5, sampleRate: 8000, seed: 7)
        let again = NoiseLoop.make(.brown, seconds: 0.5, sampleRate: 8000, seed: 7)
        let pink = NoiseLoop.make(.pink, seconds: 0.5, sampleRate: 8000, seed: 7)
        #expect(brown == again)
        #expect(brown.samples.count == 4000 && brown.sampleRate == 8000)
        #expect(brown.samples.allSatisfy { $0.isFinite } && pink.samples.allSatisfy { $0.isFinite })
        #expect(rms(brown.samples[...]) > 0 && rms(pink.samples[...]) > 0)
        // Brown falls off faster with frequency than pink: after the same normalisation, the
        // sample-to-sample differences (a crude high-pass) are smaller for brown.
        let b = Loudness.normalised(brown).samples, p = Loudness.normalised(pink).samples
        let bHigh = rms(zip(b.dropFirst(), b).map { $0 - $1 }[...])
        let pHigh = rms(zip(p.dropFirst(), p).map { $0 - $1 }[...])
        #expect(bHigh < pHigh)
    }

    @Test func normalisationHitsTheTargetOrTheCeiling() {
        let quiet = PCMAudio(sampleRate: 1000, samples: (0..<1000).map { Float(sin(Double($0) * 0.3)) * 0.01 })
        let loud = Loudness.normalised(quiet, toRMSDecibels: -20)
        #expect(abs(Loudness.decibels(rms(loud.samples[...])) - (-20)) < 0.1)
        // One spike in silence: bringing its RMS to −20 dB would put the peak past 0 dB, so the
        // ceiling wins.
        var spiky = [Float](repeating: 0, count: 100); spiky[0] = 1
        let capped = Loudness.normalised(PCMAudio(sampleRate: 1000, samples: spiky), toRMSDecibels: -20, peakCeilingDecibels: -1)
        #expect(abs(capped.samples.max()! - Loudness.linear(-1)) < 1e-4)
        #expect(Loudness.normalised(PCMAudio(sampleRate: 1000, samples: [])).samples.isEmpty)
    }

    @Test func decibelsAndLinearRoundTrip() {
        #expect(abs(Loudness.linear(-20) - 0.1) < 1e-6)
        #expect(abs(Loudness.decibels(0.5) - (-6.0206)) < 1e-3)
    }
}
