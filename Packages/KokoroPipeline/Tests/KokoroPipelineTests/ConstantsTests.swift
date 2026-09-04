import Testing
@testable import KokoroPipeline

@Suite struct ConstantsTests {
    @Test func frameAndSampleConstantsMatchTheMeasuredPipeline() {
        #expect(PipelineConstants.sampleRate == 24_000)
        #expect(PipelineConstants.samplesPerDurationFrame == 600)
        #expect(PipelineConstants.voiceEmbeddingDim == 256)
        #expect(KokoroVocabulary.bosEosTokenId == 0)
        #expect(PipelineConstants.tFramesForBucket[7] == 280 && PipelineConstants.tFramesForBucket[15] == 600)
    }
}
