import Testing
@testable import KokoroPipeline

/// The sine passes of the harmonic source stop one frame past the last voiced frame (Plan 16):
/// the mask zeroes every later sample anyway, so the trimmed source must be bit-identical to the
/// one computed over the whole padded bucket.
@Suite struct HarmonicSourceTests {
    static let weights: [Float] = [0.3, -0.2, 0.1, 0.05, -0.05, 0.02, 0.01, -0.01, 0.005]
    static let bias: Float = 0.01

    func full(_ f0: [Float]) -> [Float] {
        sineGenFromF0Frames(f0Frames: f0, linearWeights: Self.weights, linearBias: Self.bias, seed: 7, sineFrames: f0.count)
    }
    func trimmed(_ f0: [Float]) -> [Float] {
        sineGenFromF0Frames(f0Frames: f0, linearWeights: Self.weights, linearBias: Self.bias, seed: 7)
    }

    @Test func aVoicedPrefixThenPaddingIsIdenticalToTheFullComputation() {
        let f0 = (0..<12).map { Float(120 + 7 * $0) } + [5, 0] + [Float](repeating: 0, count: 26)
        #expect(sineFrameCount(f0Frames: f0) == 13)      // frames 0–11 voiced, plus the one after
        #expect(trimmed(f0) == full(f0))
        #expect(trimmed(f0).count == f0.count * HarmonicConstants.upsampleScale)
    }

    @Test func anUnvoicedGapInsideTheUtteranceKeepsEveryFrameUpToTheLastVoicedOne() {
        let f0: [Float] = [150, 160, 0, 0, 0, 170, 180, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        #expect(sineFrameCount(f0Frames: f0) == 8)
        #expect(trimmed(f0) == full(f0))
    }

    @Test func aCurveVoicedToItsLastFrameComputesEveryFrame() {
        let f0 = (0..<10).map { Float(200 + $0) }
        #expect(sineFrameCount(f0Frames: f0) == 10)
        #expect(trimmed(f0) == full(f0))
    }

    @Test func anEntirelyUnvoicedCurveSkipsTheSinePassesAndStillMatches() {
        let f0 = [Float](repeating: 0, count: 8)
        #expect(sineFrameCount(f0Frames: f0) == 0)
        #expect(trimmed(f0) == full(f0))
        #expect(sineFrameCount(f0Frames: []) == 0)
        #expect(trimmed([]) == [])
    }
}
