import Testing
@testable import KokoroPipeline

/// The pitch-spread hook (t2s_reader, `spikes/findings/2026-09-08-quality-levers.md`): voiced frames'
/// log-F0 scaled about their mean; unvoiced frames and a factor of 1 leave the curve alone.
@Suite struct SpreadF0Tests {
    @Test func aFactorOfOneReturnsTheCurveUntouched() {
        let f0: [Float] = [0, 100, 200, 0, 400]
        #expect(spreadF0(f0, by: 1) == f0)
    }

    @Test func widensAboutTheLogMeanAndLeavesUnvoicedFramesAlone() {
        // Voiced frames 100 and 400 Hz: log-mean is 200 Hz; a factor of 2 doubles each distance.
        let out = spreadF0([0, 100, 400, 5], by: 2)
        #expect(out[0] == 0 && out[3] == 5)            // 0 and 5 Hz are under the voiced threshold
        #expect(abs(out[1] - 50) < 0.01)               // 100 Hz is one octave under the mean → two
        #expect(abs(out[2] - 800) < 0.01)              // 400 Hz is one octave over → two
    }

    @Test func aFactorUnderOneNarrows() {
        let out = spreadF0([100, 400], by: 0.5)
        #expect(abs(out[0] - 141.42) < 0.05 && abs(out[1] - 282.84) < 0.05)
    }
}
