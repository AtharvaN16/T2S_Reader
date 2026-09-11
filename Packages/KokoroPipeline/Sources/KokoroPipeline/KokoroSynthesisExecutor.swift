import CoreML
import Foundation

/// Supplies Core ML models to the shared synthesis executor.
///
/// The runtime pipeline uses already-loaded model dictionaries. The benchmark
/// uses a lazy cache that can evict bucket models before loading a new bucket.
public protocol KokoroModelProvider {
    func durationModelChoices() -> [DurationModelChoice]
    func availableBucketSeconds() -> [Int]
    func durationModel(choice: DurationModelChoice) throws -> MLModel
    func f0ntrainModel(tFrames: Int) throws -> MLModel
    func decoderPreModel(bucketSec: Int) throws -> MLModel
    func generatorModel(bucketSec: Int) throws -> MLModel
    func prepareForBucket(bucketSec: Int, tFrames: Int) throws
}

public extension KokoroModelProvider {
    func prepareForBucket(bucketSec: Int, tFrames: Int) throws {}
}

/// Pre-tokenized synthesis request for the shared Swift/Core ML pipeline.
public struct KokoroSynthesisRequest {
    public let inputIds: [Int32]
    public let attentionMask: [Int32]
    public let refS: [Float]
    public let speed: Float
    public let seed: UInt64
    public let warmModelsBeforeTiming: Bool
    public let bucketDurationOverrideSeconds: Double?
    /// Which punctuation spans ``suppressPunctuationTokenAudio`` fades to silence after the trim.
    /// Upstream's default is every punctuation token; see ``PunctuationSuppression``.
    /// Vendored addition (t2s_reader).
    public let punctuationSuppression: PunctuationSuppression
    /// How much the predicted pitch contour's movement is widened before the decoder sees it: the
    /// voiced frames' log-F0 is scaled about its mean by this factor, so 1 leaves the model's own
    /// intonation and 1.5 makes every rise and fall half again as large. Vendored addition
    /// (t2s_reader, an experiment: `spikes/findings/2026-09-08-quality-levers.md`).
    public let f0Spread: Float

    public init(
        inputIds: [Int32],
        attentionMask: [Int32],
        refS: [Float],
        speed: Float = 1.0,
        seed: UInt64 = 42,
        warmModelsBeforeTiming: Bool = false,
        bucketDurationOverrideSeconds: Double? = nil,
        punctuationSuppression: PunctuationSuppression = .allPunctuation,
        f0Spread: Float = 1
    ) {
        self.inputIds = inputIds
        self.attentionMask = attentionMask
        self.refS = refS
        self.speed = speed
        self.seed = seed
        self.warmModelsBeforeTiming = warmModelsBeforeTiming
        self.bucketDurationOverrideSeconds = bucketDurationOverrideSeconds
        self.punctuationSuppression = punctuationSuppression
        self.f0Spread = f0Spread
    }
}

/// How much of the waveform ``suppressPunctuationTokenAudio`` is allowed to silence.
///
/// Vendored addition (t2s_reader, 2026-09-05). Upstream zeroes the duration span of every
/// punctuation token, quotation marks and parentheses included, with a 5 ms fade on each side.
/// Those spans are near-silent in the PyTorch reference, but the Core ML decoder does not place its
/// audio exactly where the duration model predicted, so the zeroing lands on running speech at every
/// comma and every quotation mark of a novel. The engine chooses; the pipeline's default is upstream's.
public enum PunctuationSuppression: Sendable, Hashable {
    /// Upstream behaviour: every id in ``KokoroVocabulary/silentPunctuationTokenIds``.
    case allPunctuation
    /// Only the spans of sentence-final marks — `.` `!` `?` `…` — where a real pause is predicted.
    case sentenceFinal
    /// Leave the waveform as the generator produced it (the PyTorch reference's behaviour).
    case none

    /// The token ids whose spans are faded to silence.
    public var tokenIds: Set<Int32> {
        switch self {
        case .allPunctuation: KokoroVocabulary.silentPunctuationTokenIds
        case .sentenceFinal: KokoroVocabulary.sentenceFinalPunctuationTokenIds
        case .none: []
        }
    }
}

private struct DurationInputBundle {
    let provider: MLDictionaryFeatureProvider
    let idsArray: MLMultiArray
    let maskArray: MLMultiArray?
    let refSArray: MLMultiArray
    let speedArray: MLMultiArray
}

private struct DurationProbe {
    let bucketSec: Int
    let tFrames: Int
    let fullF0Len: Int
}

/// Run the Core ML Kokoro pipeline once.
///
/// This is the single orchestration path shared by `KokoroPipeline.synthesize`
/// and the `kokoro-bench` executable. Benchmark-only behavior is injected via
/// `KokoroModelProvider.prepareForBucket(...)`, `warmModelsBeforeTiming`, and
/// the optional tensor dump writer.
public func executeKokoroSynthesis(
    request: KokoroSynthesisRequest,
    modelProvider: KokoroModelProvider,
    linearWeights: [Float],
    linearBias: Float,
    tensorDump: inout TensorDumpWriter?
) throws -> SynthesisResult {
    let durationChoices = modelProvider.durationModelChoices()
    let durationChoice = try KokoroPipeline.selectDurationChoice(
        durationChoices,
        actualTokens: requestedTokenCount(
            inputIds: request.inputIds,
            attentionMask: request.attentionMask
        )
    )
    let durationInput = try buildDurationInput(
        inputIds: request.inputIds,
        attentionMask: request.attentionMask,
        refS: request.refS,
        speed: request.speed,
        choice: durationChoice
    )
    let durationModel = try modelProvider.durationModel(choice: durationChoice)

    try writeDurationInputs(durationInput, tensorDump: &tensorDump)

    if request.warmModelsBeforeTiming {
        let probe = try probeDurationAndBucket(
            input: durationInput,
            durationModel: durationModel,
            modelProvider: modelProvider,
            validTokenLimit: validTokenCount(
                predDurTokenCount: durationChoice.tokenLength,
                attentionMask: request.attentionMask
            ),
            bucketDurationOverrideSeconds: request.bucketDurationOverrideSeconds
        )
        try warmModels(
            probe: probe,
            durationModel: durationModel,
            durationInput: durationInput.provider,
            modelProvider: modelProvider
        )
    }

    var timings = StageTimings()

    // Stage 1: Duration Core ML.
    let t0 = CFAbsoluteTimeGetCurrent()
    let durOutput = try durationModel.prediction(from: durationInput.provider)
    let t1 = CFAbsoluteTimeGetCurrent()
    timings.durationCoreML = t1 - t0

    let predDurArray = durOutput.featureValue(for: "pred_dur")!.multiArrayValue!
    let dArray = durOutput.featureValue(for: "d")!.multiArrayValue!
    let tEnArray = durOutput.featureValue(for: "t_en")!.multiArrayValue!
    let tokenCount = predDurArray.shape.last!.intValue
    let validTokens = validTokenCount(
        predDurTokenCount: tokenCount,
        attentionMask: request.attentionMask
    )
    let predDur = try readDurationFrames(from: predDurArray, validCount: validTokens)
    let frames = predDur.reduce(0, +)
    let totalSeconds = Double(frames * 2) / PipelineConstants.f0FrameRate
    let bucketSelectionSeconds = request.bucketDurationOverrideSeconds ?? totalSeconds

    try writeDurationOutputs(
        predDurArray: predDurArray,
        predDur: predDur,
        dArray: dArray,
        tEnArray: tEnArray,
        tensorDump: &tensorDump
    )

    // Stage 2: alignment metadata. Tensor dumps keep the old sparse matrix as
    // debug data; the hot path expands token vectors directly in Stage 3.
    let t2 = CFAbsoluteTimeGetCurrent()
    let alignment: [Float]? = tensorDump == nil
        ? nil
        : buildAlignmentMatrix(predDur: predDur, traceLength: tokenCount, frameCount: frames)
    let t3 = CFAbsoluteTimeGetCurrent()
    timings.alignment = t3 - t2

    if let alignment {
        try tensorDump?.writeFloatArray(
            name: "alignment",
            values: alignment,
            shape: [1, tokenCount, frames]
        )
    }

    // Stage 3: direct token-vector expansion.
    let t4 = CFAbsoluteTimeGetCurrent()
    let en = try alignTokenMajorToFrames(
        source: dArray,
        predDur: predDur,
        channels: PipelineConstants.hiddenDim,
        frameCount: frames
    )
    let asr = try alignChannelMajorToFrames(
        source: tEnArray,
        predDur: predDur,
        channels: PipelineConstants.textEncoderDim,
        frameCount: frames
    )
    let t5 = CFAbsoluteTimeGetCurrent()
    timings.matrixOps = t5 - t4

    try tensorDump?.writeMLMultiArray(name: "en", array: en)
    try tensorDump?.writeMLMultiArray(name: "asr", array: asr)

    // Stage 4: F0Ntrain Core ML.
    let t6 = CFAbsoluteTimeGetCurrent()
    guard let bucketSec = selectBucket(
        totalSeconds: bucketSelectionSeconds,
        availableBuckets: modelProvider.availableBucketSeconds()
    ) else {
        throw PipelineError.noBucketAvailable
    }
    guard let tFrames = PipelineConstants.tFramesForBucket[bucketSec] else {
        throw PipelineError.modelNotLoaded("f0ntrain bucket \(bucketSec)")
    }
    try modelProvider.prepareForBucket(bucketSec: bucketSec, tFrames: tFrames)
    let f0nModel = try modelProvider.f0ntrainModel(tFrames: tFrames)
    let enPadded = try zeroPad3D(
        source: en,
        channels: PipelineConstants.hiddenDim,
        targetTime: tFrames
    )
    let sArray = try makeZeroArray2D(dim: PipelineConstants.styleDim)
    let sPtr = sArray.dataPointer.assumingMemoryBound(to: Float.self)
    for i in 0..<PipelineConstants.styleDim {
        sPtr[i] = request.refS[PipelineConstants.baselineDim + i]
    }

    try tensorDump?.writeMLMultiArray(name: "en_padded", array: enPadded)
    try tensorDump?.writeMLMultiArray(name: "s", array: sArray)

    let f0nInput = try MLDictionaryFeatureProvider(dictionary: [
        "en": MLFeatureValue(multiArray: enPadded),
        "s": MLFeatureValue(multiArray: sArray),
    ])
    let f0nOutput = try f0nModel.prediction(from: f0nInput)
    let f0PredArray = f0nOutput.featureValue(for: "F0_pred")!.multiArrayValue!
    let nPredArray = f0nOutput.featureValue(for: "N_pred")!.multiArrayValue!
    let t7 = CFAbsoluteTimeGetCurrent()
    timings.f0ntrainCoreML = t7 - t6

    let f0Curve = spreadF0(floatValues(from: f0PredArray), by: request.f0Spread)
    let nCurve = floatValues(from: nPredArray)

    try tensorDump?.writeFloatArray(name: "f0", values: f0Curve, shape: [1, f0Curve.count])
    try tensorDump?.writeFloatArray(name: "n", values: nCurve, shape: [1, nCurve.count])

    // Stage 5: pad to bucket geometry.
    let t8 = CFAbsoluteTimeGetCurrent()
    let bucketSamples = bucketSec * PipelineConstants.sampleRate
    let fullF0Len = Int(round(Double(bucketSamples) / Double(HarmonicConstants.upsampleScale)))
    let f0Padded = zeroPad1D(source: f0Curve, targetLength: fullF0Len)
    let nPadded = zeroPad1D(source: nCurve, targetLength: fullF0Len)
    let frameCount = decoderPreFrameCount(fullF0Len: fullF0Len)
    let asrPadded = try zeroPad3D(
        source: asr,
        channels: PipelineConstants.textEncoderDim,
        targetTime: frameCount
    )
    let t9 = CFAbsoluteTimeGetCurrent()
    timings.padding = t9 - t8

    try tensorDump?.writeFloatArray(name: "f0_padded", values: f0Padded, shape: [1, fullF0Len])
    try tensorDump?.writeFloatArray(name: "n_padded", values: nPadded, shape: [1, fullF0Len])
    try tensorDump?.writeMLMultiArray(name: "asr_padded", array: asrPadded)

    // Stage 7 first: hn-nsf Swift DSP, built beside the DecoderPre prediction. It reads only
    // f0Padded and the source module's weights, so it can run on another core while Core ML
    // holds this thread; `decoderPreHnsfOverlap` records how much of it hid behind Stage 6.
    // Vendored change (t2s_reader, Plan 16); upstream ran the two one after the other.
    let har = HarBuild()
    let harGroup = DispatchGroup()
    let wantsHarComponents = tensorDump != nil
    let harSeed = request.seed
    DispatchQueue.global(qos: .userInitiated).async(group: harGroup) {
        har.started = CFAbsoluteTimeGetCurrent()
        if wantsHarComponents {
            let components = buildHarComponents(
                f0Padded: f0Padded,
                linearWeights: linearWeights,
                linearBias: linearBias,
                seed: harSeed
            )
            har.flat = components.har
            har.frames = components.nFrames
            har.debug = components
        } else {
            let built = buildHar(
                f0Padded: f0Padded,
                linearWeights: linearWeights,
                linearBias: linearBias,
                seed: harSeed
            )
            har.flat = built.har
            har.frames = built.nFrames
        }
        har.finished = CFAbsoluteTimeGetCurrent()
    }
    defer { harGroup.wait() }   // on every exit, a throw included: the build must not outlive the call

    // Stage 6: DecoderPre Core ML.
    let t10 = CFAbsoluteTimeGetCurrent()
    let decPreModel = try modelProvider.decoderPreModel(bucketSec: bucketSec)
    let f0Array3D = try makeZeroArray3D(channels: 1, time: fullF0Len)
    copyInto(array: f0Array3D, from: f0Padded)
    let nArray3D = try makeZeroArray3D(channels: 1, time: fullF0Len)
    copyInto(array: nArray3D, from: nPadded)
    let decRefS = try makeZeroArray2D(dim: PipelineConstants.voiceEmbeddingDim)
    copyInto(array: decRefS, from: request.refS)

    let decPreInput = try MLDictionaryFeatureProvider(dictionary: [
        "asr": MLFeatureValue(multiArray: asrPadded),
        "f0": MLFeatureValue(multiArray: f0Array3D),
        "n_input": MLFeatureValue(multiArray: nArray3D),
        "ref_s": MLFeatureValue(multiArray: decRefS),
    ])
    let decPreOutput = try decPreModel.prediction(from: decPreInput)
    let t11 = CFAbsoluteTimeGetCurrent()
    timings.decoderPre = t11 - t10
    let xPre = decPreOutput.featureValue(for: "x_pre")!.multiArrayValue!

    try tensorDump?.writeMLMultiArray(name: "x_pre", array: xPre)

    harGroup.wait()
    let harFlat = har.flat
    let harFrames = har.frames
    let harDebug = har.debug
    timings.hnsfSwift = har.finished - har.started                       // the build itself, not the queue's latency
    timings.decoderPreHnsfOverlap = max(0, min(t11, har.finished) - max(t10, har.started))

    if let harDebug {
        try tensorDump?.writeFloatArray(
            name: "har_source",
            values: harDebug.harSource,
            shape: [1, harDebug.harSource.count]
        )
        try tensorDump?.writeFloatArray(
            name: "har_magnitude",
            values: harDebug.magnitude,
            shape: [1, 11, harDebug.nFrames]
        )
        try tensorDump?.writeFloatArray(
            name: "har_phase",
            values: harDebug.phase,
            shape: [1, 11, harDebug.nFrames]
        )
    }
    try tensorDump?.writeFloatArray(name: "har", values: harFlat, shape: [1, 22, harFrames])

    // Stage 8: GeneratorFromHar Core ML.
    let t14 = CFAbsoluteTimeGetCurrent()
    let genModel = try modelProvider.generatorModel(bucketSec: bucketSec)
    let genRefS = try makeZeroArray2D(dim: PipelineConstants.voiceEmbeddingDim)
    copyInto(array: genRefS, from: request.refS)

    let genShapes = inputShapes(from: genModel)
    let xPreExpectedTime = genShapes["x_pre"]?.last ?? xPre.shape.last!.intValue
    let harExpectedTime = genShapes["har"]?.last ?? harFrames
    let xPrePadded = try zeroPad3D(
        source: xPre,
        channels: xPre.shape[1].intValue,
        targetTime: xPreExpectedTime
    )
    let harPadded = try zeroPad3D(
        sourceValues: harFlat,
        channels: HarmonicConstants.harChannels,
        sourceTime: harFrames,
        targetTime: harExpectedTime
    )

    try tensorDump?.writeMLMultiArray(name: "x_pre_padded", array: xPrePadded)
    try tensorDump?.writeMLMultiArray(name: "har_padded", array: harPadded)

    let genInput = try MLDictionaryFeatureProvider(dictionary: [
        "x_pre": MLFeatureValue(multiArray: xPrePadded),
        "ref_s": MLFeatureValue(multiArray: genRefS),
        "har": MLFeatureValue(multiArray: harPadded),
    ])
    let genOutput = try genModel.prediction(from: genInput)
    let t15 = CFAbsoluteTimeGetCurrent()
    timings.generatorCoreML = t15 - t14

    // Stage 9: trim waveform.
    let t16 = CFAbsoluteTimeGetCurrent()
    let waveformKey = genOutput.featureNames.contains("waveform") ? "waveform" : genOutput.featureNames.first!
    let waveformArray = genOutput.featureValue(for: waveformKey)!.multiArrayValue!
    let originalF0Len = frames * 2
    let targetLen = Int(
        round(Double(originalF0Len) / PipelineConstants.f0FrameRate * Double(PipelineConstants.sampleRate))
    )
    let trimLen = min(waveformArray.count, targetLen)
    let rawAudio = floatValues(from: waveformArray, limit: trimLen)
    // Upstream asserted here (DEBUG only) when the predicted span overran the bucket. Vendored
    // change (t2s_reader, 2026-09-08): the caller checks `predictedDurationFrames` against
    // `bucketSeconds` on every result and re-splits an overflowing piece (`KokoroCoreMLEngine`,
    // Plan 9 Task 1), so the condition is handled, not a bug — and a debug build on a phone is a
    // real reader's build. A slow voice (`af_nicole`) on one 160-character utterance predicted 16.7 s
    // for the 15 s bucket and took the whole process down with the assertion.
    let audio = suppressPunctuationTokenAudio(
        rawAudio,
        inputIds: Array(request.inputIds.prefix(predDur.count)),
        predDur: predDur,
        suppressedTokenIds: request.punctuationSuppression.tokenIds
    )
    let t17 = CFAbsoluteTimeGetCurrent()
    timings.trim = t17 - t16

    if tensorDump != nil {
        let waveformValues = floatValues(from: waveformArray)
        try tensorDump?.writeFloatArray(
            name: "waveform_full",
            values: waveformValues,
            shape: waveformArray.shape.map { $0.intValue }
        )
        try tensorDump?.writeFloatArray(name: "waveform_raw_trimmed", values: rawAudio, shape: [trimLen])
        try tensorDump?.writeFloatArray(name: "waveform", values: audio, shape: [trimLen])
    }

    return SynthesisResult(
        audio: audio,
        timings: timings,
        bucketSeconds: bucketSec,
        audioDurationSeconds: Double(originalF0Len) / PipelineConstants.f0FrameRate,
        wallTimeSeconds: t17 - t0,
        predictedDurationFrames: frames,
        predictedDurationTokens: predDur.count,
        durationModelCacheKey: durationChoice.cacheKey,
        durationModelAllowsPadding: durationChoice.allowsPadding,
        durationTokenLength: durationChoice.tokenLength,
        tFrames: tFrames,
        fullF0Length: fullF0Len,
        decoderFrameCount: frameCount,
        xPreExpectedTime: xPreExpectedTime,
        harExpectedTime: harExpectedTime,
        trimSampleCount: trimLen,
        tokenDurationFrames: predDur
    )
}

private func requestedTokenCount(inputIds: [Int32], attentionMask: [Int32]) -> Int {
    let maskedTokenCount = attentionMask.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
    return maskedTokenCount > 0 ? maskedTokenCount : inputIds.count
}

private func validTokenCount(predDurTokenCount: Int, attentionMask: [Int32]) -> Int {
    min(predDurTokenCount, attentionMask.reduce(0) { $0 + ($1 == 0 ? 0 : 1) })
}

private func buildDurationInput(
    inputIds: [Int32],
    attentionMask: [Int32],
    refS: [Float],
    speed: Float,
    choice: DurationModelChoice
) throws -> DurationInputBundle {
    let tokenLength = choice.tokenLength
    let idsArray = try MLMultiArray(shape: [1, NSNumber(value: tokenLength)], dataType: .int32)
    let maskArray = choice.requiresAttentionMask
        ? try MLMultiArray(shape: [1, NSNumber(value: tokenLength)], dataType: .int32)
        : nil
    let refSArray = try makeZeroArray2D(dim: PipelineConstants.voiceEmbeddingDim)
    let speedArray = try MLMultiArray(shape: [1], dataType: .float32)

    let idsPtr = idsArray.dataPointer.assumingMemoryBound(to: Int32.self)
    let refSPtr = refSArray.dataPointer.assumingMemoryBound(to: Float.self)
    for i in 0..<min(inputIds.count, tokenLength) {
        idsPtr[i] = inputIds[i]
    }
    if let maskArray {
        let maskPtr = maskArray.dataPointer.assumingMemoryBound(to: Int32.self)
        for i in 0..<min(attentionMask.count, tokenLength) {
            maskPtr[i] = attentionMask[i]
        }
    }
    for i in 0..<min(refS.count, PipelineConstants.voiceEmbeddingDim) {
        refSPtr[i] = refS[i]
    }
    speedArray[0] = NSNumber(value: speed)

    var features: [String: MLFeatureValue] = [
        "input_ids": MLFeatureValue(multiArray: idsArray),
        "ref_s": MLFeatureValue(multiArray: refSArray),
        "speed": MLFeatureValue(multiArray: speedArray),
    ]
    if let maskArray {
        features["attention_mask"] = MLFeatureValue(multiArray: maskArray)
    }

    return DurationInputBundle(
        provider: try MLDictionaryFeatureProvider(dictionary: features),
        idsArray: idsArray,
        maskArray: maskArray,
        refSArray: refSArray,
        speedArray: speedArray
    )
}

private func writeDurationInputs(
    _ input: DurationInputBundle,
    tensorDump: inout TensorDumpWriter?
) throws {
    try tensorDump?.writeMLMultiArray(name: "tokens", array: input.idsArray)
    if let maskArray = input.maskArray {
        try tensorDump?.writeMLMultiArray(name: "attention_mask", array: maskArray)
    }
    try tensorDump?.writeMLMultiArray(name: "ref_s", array: input.refSArray)
    try tensorDump?.writeMLMultiArray(name: "speed", array: input.speedArray)
}

private func writeDurationOutputs(
    predDurArray: MLMultiArray,
    predDur: [Int],
    dArray: MLMultiArray,
    tEnArray: MLMultiArray,
    tensorDump: inout TensorDumpWriter?
) throws {
    try tensorDump?.writeMLMultiArray(name: "pred_dur", array: predDurArray)
    try tensorDump?.writeInt32Array(
        name: "pred_dur_valid",
        values: predDur.map { Int32($0) },
        shape: [1, predDur.count]
    )
    try tensorDump?.writeMLMultiArray(name: "duration_d", array: dArray)
    try tensorDump?.writeMLMultiArray(name: "duration_t_en", array: tEnArray)
}

private func probeDurationAndBucket(
    input: DurationInputBundle,
    durationModel: MLModel,
    modelProvider: KokoroModelProvider,
    validTokenLimit: Int,
    bucketDurationOverrideSeconds: Double?
) throws -> DurationProbe {
    let output = try durationModel.prediction(from: input.provider)
    let predDurArray = output.featureValue(for: "pred_dur")!.multiArrayValue!
    let predDur = try readDurationFrames(from: predDurArray, validCount: validTokenLimit)
    let totalFrames = predDur.reduce(0, +)
    let totalSeconds = Double(totalFrames * 2) / PipelineConstants.f0FrameRate
    guard let bucketSec = selectBucket(
        totalSeconds: bucketDurationOverrideSeconds ?? totalSeconds,
        availableBuckets: modelProvider.availableBucketSeconds()
    ) else {
        throw PipelineError.noBucketAvailable
    }
    guard let tFrames = PipelineConstants.tFramesForBucket[bucketSec] else {
        throw PipelineError.modelNotLoaded("f0ntrain bucket \(bucketSec)")
    }
    try modelProvider.prepareForBucket(bucketSec: bucketSec, tFrames: tFrames)
    let bucketSamples = bucketSec * PipelineConstants.sampleRate
    let fullF0Len = Int(round(Double(bucketSamples) / Double(HarmonicConstants.upsampleScale)))
    return DurationProbe(
        bucketSec: bucketSec,
        tFrames: tFrames,
        fullF0Len: fullF0Len
    )
}

private func warmModels(
    probe: DurationProbe,
    durationModel: MLModel,
    durationInput: MLDictionaryFeatureProvider,
    modelProvider: KokoroModelProvider
) throws {
    _ = try durationModel.prediction(from: durationInput)
    try warmBucketStages(probe: probe, modelProvider: modelProvider)
}

/// Runs each listed duration model and each listed bucket's three stages once, on zero inputs, so
/// their first real prediction pays no specialization. Vendored addition (t2s_reader, 2026-09-10):
/// on the GPU, Core ML finishes specializing a stage at its first prediction — 4–5 s for the t128
/// duration model and 14–15 s for t256 on an iPhone 17 Pro, on every launch and whatever the
/// load-time hint — and the app would rather spend that just after its stages load than on the
/// first sentence a reader is waiting for. A token length or bucket the provider lacks is skipped.
public func warmKokoroStages(modelProvider: KokoroModelProvider, tokenLengths: [Int], buckets: [Int]) throws {
    let choices = modelProvider.durationModelChoices()
    for tokens in tokenLengths {
        guard let choice = choices.first(where: { $0.tokenLength == tokens }) else { continue }
        // Real ids throughout — the boundary token — under a full mask: `buildDurationInput` copies
        // into a buffer it does not zero, and an embedding lookup must never read what was there.
        let input = try buildDurationInput(
            inputIds: Array(repeating: KokoroVocabulary.bosEosTokenId, count: tokens),
            attentionMask: Array(repeating: 1, count: tokens),
            refS: Array(repeating: 0, count: PipelineConstants.voiceEmbeddingDim),
            speed: 1,
            choice: choice
        )
        _ = try modelProvider.durationModel(choice: choice).prediction(from: input.provider)
    }
    let available = modelProvider.availableBucketSeconds()
    for bucketSec in buckets where available.contains(bucketSec) {
        guard let tFrames = PipelineConstants.tFramesForBucket[bucketSec] else { continue }
        let bucketSamples = bucketSec * PipelineConstants.sampleRate
        let fullF0Len = Int(round(Double(bucketSamples) / Double(HarmonicConstants.upsampleScale)))
        try warmBucketStages(probe: DurationProbe(bucketSec: bucketSec, tFrames: tFrames, fullF0Len: fullF0Len),
                             modelProvider: modelProvider)
    }
}

/// The bucket half of ``warmModels``: F0Ntrain, DecoderPre and the generator once each on zeros.
private func warmBucketStages(probe: DurationProbe, modelProvider: KokoroModelProvider) throws {
    let f0nModel = try modelProvider.f0ntrainModel(tFrames: probe.tFrames)
    let warmEnArr = try makeZeroArray3D(
        channels: PipelineConstants.hiddenDim,
        time: probe.tFrames
    )
    let warmSArr = try makeZeroArray2D(dim: PipelineConstants.styleDim)
    let warmF0nIn = try MLDictionaryFeatureProvider(dictionary: [
        "en": MLFeatureValue(multiArray: warmEnArr),
        "s": MLFeatureValue(multiArray: warmSArr),
    ])
    _ = try f0nModel.prediction(from: warmF0nIn)

    let decPreModel = try modelProvider.decoderPreModel(bucketSec: probe.bucketSec)
    let warmFrameCount = decoderPreFrameCount(fullF0Len: probe.fullF0Len)
    let warmAsr = try makeZeroArray3D(
        channels: PipelineConstants.textEncoderDim,
        time: warmFrameCount
    )
    let warmF0 = try makeZeroArray3D(channels: 1, time: probe.fullF0Len)
    let warmN = try makeZeroArray3D(channels: 1, time: probe.fullF0Len)
    let warmRefS = try makeZeroArray2D(dim: PipelineConstants.voiceEmbeddingDim)
    let warmDecIn = try MLDictionaryFeatureProvider(dictionary: [
        "asr": MLFeatureValue(multiArray: warmAsr),
        "f0": MLFeatureValue(multiArray: warmF0),
        "n_input": MLFeatureValue(multiArray: warmN),
        "ref_s": MLFeatureValue(multiArray: warmRefS),
    ])
    _ = try decPreModel.prediction(from: warmDecIn)

    let genModel = try modelProvider.generatorModel(bucketSec: probe.bucketSec)
    let genShapes = inputShapes(from: genModel)
    var warmGenInputs: [String: MLFeatureValue] = [:]
    for (name, shape) in genShapes {
        if shape.count == 3 {
            warmGenInputs[name] = MLFeatureValue(
                multiArray: try makeZeroArray3D(channels: shape[1], time: shape[2])
            )
        } else if shape.count == 2 {
            warmGenInputs[name] = MLFeatureValue(
                multiArray: try makeZeroArray2D(dim: shape[1])
            )
        }
    }
    _ = try genModel.prediction(from: try MLDictionaryFeatureProvider(dictionary: warmGenInputs))
}

/// The hn-nsf build's result, filled on the queue that built it and read after the group's
/// wait (which orders the two). Vendored change (t2s_reader, Plan 16).
private final class HarBuild {
    var flat: [Float] = []
    var frames = 0
    var debug: HarDebugComponents?
    var started: CFAbsoluteTime = 0
    var finished: CFAbsoluteTime = 0
}

private func decoderPreFrameCount(fullF0Len: Int) -> Int {
    (fullF0Len - 1) / 2 + 1
}

/// Widens (or narrows) the pitch contour's movement about its own mean: every voiced frame's log-F0
/// distance from the mean log-F0 is multiplied by `factor`; unvoiced frames (at or under the
/// harmonic source's voiced threshold) are left alone, so voicing decisions do not change. Vendored
/// addition (t2s_reader); `factor == 1` returns the curve untouched.
func spreadF0(_ f0: [Float], by factor: Float) -> [Float] {
    guard factor != 1, !f0.isEmpty else { return f0 }
    let threshold = HarmonicConstants.voicedThreshold
    var sum: Double = 0
    var count = 0
    for value in f0 where value > threshold { sum += log(Double(value)); count += 1 }
    guard count > 0 else { return f0 }
    let mean = sum / Double(count)
    return f0.map { value in
        guard value > threshold else { return value }
        return Float(exp(mean + Double(factor) * (log(Double(value)) - mean)))
    }
}
