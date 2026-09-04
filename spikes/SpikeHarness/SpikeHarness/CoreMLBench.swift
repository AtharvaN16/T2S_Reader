// Plan 0 Task 8 (spec §7.3 addendum) — the Core ML arm of the spike harness.
//
// Asks one question the desk research could not: does Kokoro run at all on an A13, where
// kokoro-ios/MLX traps in Metal's steel GEMM kernels (Apple GPU family 7 required)?
//
// The runtime is mattmireles/kokoro-coreml's low-level `KokoroPipeline` package: token IDs in,
// PCM plus per-input-token duration frames out, four fp16 Core ML stages plus Swift/Accelerate DSP.
// Front half (text → Misaki phonemes → Kokoro token IDs) is ours, so the same MisakiSwift 1.0.6 the
// MLX arm uses feeds both engines.
//
// Throwaway spike code: nothing under spikes/ ships.
import Foundation
import UIKit
import CoreML
import KokoroPipeline
import MisakiSwift
import MLXUtilsLibrary   // MToken
import MLX               // MisakiSwift's fallback G2P network is MLX; keep it off this GPU

/// Per-stage Core ML compute units.
///
/// `default` is `KokoroComputePolicy.gistDefault` from the upstream high-level SDK
/// (swift-tts/Sources/KokoroTTS/KokoroComputePolicy.swift) — the policy the author actually ships
/// for iPhones. Note it differs from `KokoroPipeline.init`'s own hard-coded units, which put the
/// duration model on `.cpuAndGPU`; the SDK moved that stage to the CPU because "the padded duration
/// graph can spend minutes in MPSGraph specialization on recent iOS builds". That is why this arm
/// vends its own models instead of using `KokoroPipeline` directly.
struct CoreMLStagePolicy {
    let name: String
    let duration: MLComputeUnits
    let f0ntrain: MLComputeUnits
    let decoderPre: MLComputeUnits
    let generator: MLComputeUnits

    static let gistDefault = CoreMLStagePolicy(
        name: "default",
        duration: .cpuOnly, f0ntrain: .cpuAndGPU,
        decoderPre: .cpuAndNeuralEngine, generator: .cpuAndGPU
    )

    static let cpuOnly = CoreMLStagePolicy(
        name: "cpuOnly",
        duration: .cpuOnly, f0ntrain: .cpuOnly, decoderPre: .cpuOnly, generator: .cpuOnly
    )

    static let all: [CoreMLStagePolicy] = [.gistDefault, .cpuOnly]

    /// Case- and whitespace-insensitive; `nil` for anything unrecognised so the caller can log a
    /// `policy.unknown` row instead of silently measuring a policy nobody asked for.
    static func named(_ raw: String) -> CoreMLStagePolicy? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.first { $0.name.lowercased() == key }
    }

    static var knownNames: String { all.map(\.name).joined(separator: "|") }
}

/// Serves the Xcode-precompiled `.mlmodelc` bundles to `executeKokoroSynthesis`.
///
/// Mirrors `BundleModelCache` in the upstream repo's `ios-bench/Sources/BenchApp.swift`: Xcode runs
/// coremlc at build time, so loading is a plain `MLModel(contentsOf:)` with no on-device compile.
///
/// Every staged bucket and duration size is vended, because the executor's own `selectBucket` and
/// `KokoroPipeline.selectDurationChoice` do the picking and both take what this provider offers. A
/// single-bucket provider is not a smaller staging of the same measurement — it silently runs every
/// utterance through the one geometry it has, which is most of the work in `decoderPre` and the
/// generator. `SPIKE_COREML_BUCKETS` and `SPIKE_COREML_DURATION_TOKENS` narrow the set for the
/// isolation runs (e.g. `15` alone reproduces the 8a staging).
final class CoreMLModelBundle: KokoroModelProvider {
    /// What scripts/fetch-kokoro-coreml.sh stages, and the default the harness vends.
    static let stagedBuckets = [7, 15]
    static let stagedDurationTokenLengths = [128, 256]

    private let durationModels: [Int: MLModel]     // token length -> model
    private let f0ntrainModels: [Int: MLModel]     // tFrames -> model
    private let decoderPreModels: [Int: MLModel]   // bucket seconds -> model
    private let generatorModels: [Int: MLModel]    // bucket seconds -> model
    let buckets: [Int]
    let choices: [DurationModelChoice]
    /// Largest staged duration model; the caller pads `inputIds` to this and the executor copies
    /// only the prefix the chosen model needs.
    let maxDurationTokenLength: Int
    /// Best in-process hint for which stage a first-predict failure came from.
    private(set) var lastVendedStage = ""

    init(policy: CoreMLStagePolicy,
         buckets: [Int] = CoreMLModelBundle.stagedBuckets,
         durationTokenLengths: [Int] = CoreMLModelBundle.stagedDurationTokenLengths) throws {
        guard !buckets.isEmpty, !durationTokenLengths.isEmpty else {
            throw CoreMLBench.Failure.badResource("no buckets or duration sizes selected")
        }
        self.buckets = buckets.sorted()
        maxDurationTokenLength = durationTokenLengths.max()!

        func config(_ units: MLComputeUnits) -> MLModelConfiguration {
            let c = MLModelConfiguration()
            c.computeUnits = units
            return c
        }
        // One row per stage: `MLModel(contentsOf:)` builds the compute plan (ANE compile, MPSGraph
        // specialization), and on older silicon that is where the minutes go. Without these rows a
        // slow load is indistinguishable from a hang. `thermal` is on the row because a load this
        // long is itself part of the thermal series.
        func load(_ name: String, _ units: MLComputeUnits) throws -> MLModel {
            let url = try Self.compiledURL(name)
            let t = Date()
            let model = try MLModel(contentsOf: url, configuration: config(units))
            SpikeLog.shared.record("model.stage", [
                "name": name, "units": "\(units.rawValue)",
                "seconds": String(format: "%.2f", Date().timeIntervalSince(t)),
                "footprintMB": "\(SynthBench.footprintMB())",
                "thermal": "\(ProcessInfo.processInfo.thermalState.rawValue)",
            ])
            return model
        }

        var durations: [Int: MLModel] = [:]
        var madeChoices: [DurationModelChoice] = []
        // Ascending, because `selectDurationChoice` returns the first padded choice that fits and
        // upstream sorts its choices the same way — smallest model that can hold the tokens wins.
        for tokens in durationTokenLengths.sorted() {
            let name = "kokoro_duration_t\(tokens)"
            durations[tokens] = try load(name, policy.duration)
            madeChoices.append(DurationModelChoice(
                cacheKey: "padded_t\(tokens)",
                tokenLength: tokens,
                packageURL: try Self.compiledURL(name),
                requiresAttentionMask: true,
                allowsPadding: true
            ))
        }
        durationModels = durations
        choices = madeChoices

        var f0n: [Int: MLModel] = [:]
        var pre: [Int: MLModel] = [:]
        var gen: [Int: MLModel] = [:]
        for sec in self.buckets {
            guard let tFrames = PipelineConstants.tFramesForBucket[sec] else {
                throw CoreMLBench.Failure.badResource("no tFrames mapping for bucket \(sec)s")
            }
            if f0n[tFrames] == nil {
                f0n[tFrames] = try load("kokoro_f0ntrain_t\(tFrames)", policy.f0ntrain)
            }
            pre[sec] = try load("kokoro_decoder_pre_\(sec)s", policy.decoderPre)
            gen[sec] = try load("kokoro_decoder_har_post_\(sec)s", policy.generator)
        }
        f0ntrainModels = f0n
        decoderPreModels = pre
        generatorModels = gen
    }

    private static func compiledURL(_ name: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw CoreMLBench.Failure.missingModel("\(name).mlmodelc")
        }
        return url
    }

    func durationModelChoices() -> [DurationModelChoice] { choices }
    func availableBucketSeconds() -> [Int] { buckets }

    func durationModel(choice: DurationModelChoice) throws -> MLModel {
        lastVendedStage = "duration"
        guard let m = durationModels[choice.tokenLength] else {
            throw CoreMLBench.Failure.missingModel("duration t\(choice.tokenLength)")
        }
        return m
    }
    func f0ntrainModel(tFrames: Int) throws -> MLModel {
        lastVendedStage = "f0ntrain"
        guard let m = f0ntrainModels[tFrames] else {
            throw CoreMLBench.Failure.missingModel("f0ntrain t\(tFrames)")
        }
        return m
    }
    func decoderPreModel(bucketSec: Int) throws -> MLModel {
        lastVendedStage = "decoderPre"
        guard let m = decoderPreModels[bucketSec] else {
            throw CoreMLBench.Failure.missingModel("decoder_pre \(bucketSec)s")
        }
        return m
    }
    func generatorModel(bucketSec: Int) throws -> MLModel {
        lastVendedStage = "generator"
        guard let m = generatorModels[bucketSec] else {
            throw CoreMLBench.Failure.missingModel("decoder_har_post \(bucketSec)s")
        }
        return m
    }
}

/// Kokoro's 178-symbol vocabulary and the `[Float]` voice table, both from the model repo.
struct KokoroTokenizer {
    let vocab: [String: Int32]
    /// Row-major `[rows][256]` float32 voice embedding table.
    private let voiceRows: [Float]
    let voiceRowCount: Int

    /// BOS/EOS boundary and padding token; `KokoroVocabulary.bosEosTokenId`.
    static let boundary = KokoroVocabulary.bosEosTokenId

    init(vocabURL: URL, voiceURL: URL) throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: vocabURL))
        guard let dict = json as? [String: Any], let raw = dict["vocab"] as? [String: Any] else {
            throw CoreMLBench.Failure.badResource("kokoro-vocab.json has no vocab object")
        }
        var table: [String: Int32] = [:]
        for (symbol, value) in raw {
            guard let number = value as? NSNumber else {
                throw CoreMLBench.Failure.badResource("kokoro-vocab.json entry \(symbol) is not a number")
            }
            table[symbol] = number.int32Value
        }
        vocab = table

        let data = try Data(contentsOf: voiceURL)
        let stride = PipelineConstants.voiceEmbeddingDim * 4
        guard !data.isEmpty, data.count % stride == 0 else {
            throw CoreMLBench.Failure.badResource("voice table is \(data.count) bytes, not a multiple of \(stride)")
        }
        var floats = [Float](repeating: 0, count: data.count / 4)
        data.withUnsafeBytes { raw in
            for i in 0..<floats.count {
                floats[i] = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)))
            }
        }
        voiceRows = floats
        voiceRowCount = data.count / stride
    }

    /// Voice row for a chunk, by the fleet rule in the SDK's `VoiceTable.refS`:
    /// `clamp(phonemeCount - 1, 0, rows - 1)` over the *unframed* phoneme string's UTF-16 length.
    func refS(phonemeCount: Int) -> [Float] {
        let dim = PipelineConstants.voiceEmbeddingDim
        let row = max(0, min(voiceRowCount - 1, phonemeCount - 1))
        return Array(voiceRows[(row * dim)..<((row + 1) * dim)])
    }

    /// Maps phoneme characters to token IDs, remembering which Misaki word each ID came from.
    ///
    /// `EnglishG2P.phonemize` builds its returned string as
    /// `tokens.map { ($0.phonemes ?? unk) + $0.whitespace }.joined()`, so walking the tokens in
    /// order reproduces the exact character spans. Characters with no vocab entry — including
    /// Misaki's `❓` unknown marker — are dropped, matching the SDK's tokenizer.
    func tokenize(tokens: [MToken], unknown: String = "❓") -> (ids: [Int32], owners: [Int], dropped: Int) {
        var ids: [Int32] = []
        var owners: [Int] = []
        var dropped = 0
        for (index, token) in tokens.enumerated() {
            for character in (token.phonemes ?? unknown) + token.whitespace {
                if let id = vocab[String(character)] {
                    ids.append(id)
                    owners.append(index)
                } else {
                    dropped += 1
                }
            }
        }
        return (ids, owners, dropped)
    }
}

/// Loops the Core ML Kokoro pipeline over the corpus, logging the same rows as `SynthBench`.
final class CoreMLBench: Bench, @unchecked Sendable {
    enum Failure: LocalizedError {
        case missingModel(String), missingResource(String), badResource(String)
        var errorDescription: String? {
            switch self {
            case .missingModel(let n):
                return "\(n) is not in the bundle. Run scripts/fetch-kokoro-coreml.sh, then xcodegen generate."
            case .missingResource(let n):
                return "\(n) is not in the bundle. Run scripts/fetch-kokoro-coreml.sh."
            case .badResource(let m):
                return m
            }
        }
    }

    let voiceName: String
    let policy: CoreMLStagePolicy
    private let models: CoreMLModelBundle
    private let tokenizer: KokoroTokenizer
    private let g2p: EnglishG2P
    private let linearWeights: [Float]
    private let linearBias: Float
    private var stopped = false

    init(voiceName: String = "af_heart",
         policy: CoreMLStagePolicy = .gistDefault,
         buckets: [Int] = CoreMLModelBundle.stagedBuckets,
         durationTokenLengths: [Int] = CoreMLModelBundle.stagedDurationTokenLengths) throws {
        self.voiceName = voiceName
        self.policy = policy
        func url(_ name: String, _ ext: String) throws -> URL {
            guard let u = Bundle.main.url(forResource: name, withExtension: ext) else {
                throw Failure.missingResource("\(name).\(ext)")
            }
            return u
        }
        let t0 = Date()
        // hn-NSF `l_linear` weights, the one piece of the vocoder that stayed in Swift.
        struct HnsfWeights: Decodable { let linear_weights: [Float]; let linear_bias: Float }
        let weights = try JSONDecoder().decode(
            HnsfWeights.self, from: Data(contentsOf: try url("hnsf_weights", "json")))
        linearWeights = weights.linear_weights
        linearBias = weights.linear_bias
        tokenizer = try KokoroTokenizer(
            vocabURL: try url("kokoro-vocab", "json"), voiceURL: try url(voiceName, "bin"))
        let tTokenizer = Date()
        // MisakiSwift's out-of-lexicon fallback is a BART model on MLX, whose GEMMs are exactly what
        // an A13 cannot run. Pin MLX to the CPU so a rare unknown word cannot take the Core ML arm
        // down with an unrelated Metal trap; G2P is a few ms either way.
        MLX.Device.setDefault(device: .cpu)
        g2p = EnglishG2P(british: false)
        let tG2P = Date()
        models = try CoreMLModelBundle(policy: policy, buckets: buckets, durationTokenLengths: durationTokenLengths)
        SpikeLog.shared.record("model.loaded", [
            "engine": "coreml",
            "policy": policy.name,
            "seconds": String(format: "%.2f", Date().timeIntervalSince(t0)),
            "tokenizerSeconds": String(format: "%.2f", tTokenizer.timeIntervalSince(t0)),
            "g2pSeconds": String(format: "%.2f", tG2P.timeIntervalSince(tTokenizer)),
            "modelSeconds": String(format: "%.2f", Date().timeIntervalSince(tG2P)),
            "footprintMB": "\(SynthBench.footprintMB())",
            "voiceRows": "\(tokenizer.voiceRowCount)",
            "vocab": "\(tokenizer.vocab.count)",
            "buckets": models.buckets.map(String.init).joined(separator: "+"),
            "durationTokens": models.choices.map { "\($0.tokenLength)" }.joined(separator: "+"),
        ])
    }

    func cancel() { stopped = true }

    /// Blocking; call on a background queue. Same contract as `SynthBench.run`.
    func run(sentences: [String], cycle: BenchCycle, onProgress: @escaping @Sendable (BenchProgress) -> Void) {
        stopped = false
        SpikeLog.shared.record("bench.start", [
            "engine": "coreml", "policy": policy.name, "rate": "\(cycle.playbackRate)",
            "voice": voiceName, "sentences": "\(sentences.count)",
        ])
        var i = 0
        var progress = BenchProgress()
        while !stopped, !sentences.isEmpty {
          // One pool per sentence. Core ML and Metal autorelease per prediction — feature
          // providers, every `multiArrayValue`, the `modelDescription` walk `inputShapes(from:)`
          // does each call, the command buffers of the two `.cpuAndGPU` stages — and the whole run
          // is a single work item on a global queue, which has no pool of its own that drains
          // between iterations. Without this, everything autoreleased since `bench.start`
          // accumulates until the run ends, and a footprint curve cannot tell a runtime leak from
          // the harness holding the bag.
          autoreleasepool {
            let text = sentences[i % sentences.count]
            // Written before the call so a trap or a stall inside Core ML is attributable: the last
            // `sentence.begin` without a matching `sentence` row is the one that did not come back.
            SpikeLog.shared.record("sentence.begin", ["i": "\(i)", "chars": "\(text.utf16.count)"])
            let t0 = Date()
            var samples: [Float] = []
            var errorText = ""
            var result: SynthesisResult?
            var words: [MToken] = []
            var owners: [Int] = []
            var dropped = 0
            var g2pSeconds = 0.0
            var tokenCount = 0
            do {
                // MLX default device is .cpu for the whole arm (see init); the task-local override
                // covers this thread too, since MisakiSwift may consult either.
                let (phonemes, tokens) = MLX.Device.withDefaultDevice(.cpu) { g2p.phonemize(text: text) }
                g2pSeconds = Date().timeIntervalSince(t0)
                words = tokens
                let tokenization = tokenizer.tokenize(tokens: tokens)
                owners = tokenization.owners
                dropped = tokenization.dropped
                let framed = [KokoroTokenizer.boundary] + tokenization.ids + [KokoroTokenizer.boundary]
                tokenCount = framed.count
                guard framed.count <= models.maxDurationTokenLength else {
                    throw Failure.badResource(
                        "sentence is \(framed.count) tokens, over the \(models.maxDurationTokenLength)-token duration model")
                }
                // The duration models are static-shape: pad ids with the boundary token and the mask
                // with 0. `buildDurationInput` copies only what the caller supplies into an
                // MLMultiArray it does not zero, so padding here is required. Pad to the *largest*
                // staged model and let `selectDurationChoice` pick the smallest that fits: it copies
                // `min(inputIds.count, choice.tokenLength)` entries, so the prefix it takes is the
                // framed ids plus boundary padding either way, and the mask's zeroes tell it where
                // the real tokens end.
                let pad = models.maxDurationTokenLength - framed.count
                let inputIds = framed + Array(repeating: KokoroTokenizer.boundary, count: pad)
                let mask = Array(repeating: Int32(1), count: framed.count) + Array(repeating: Int32(0), count: pad)
                var dump: TensorDumpWriter? = nil
                result = try executeKokoroSynthesis(
                    request: KokoroSynthesisRequest(
                        inputIds: inputIds,
                        attentionMask: mask,
                        refS: tokenizer.refS(phonemeCount: phonemes.utf16.count),
                        speed: 1.0
                    ),
                    modelProvider: models,
                    linearWeights: linearWeights,
                    linearBias: linearBias,
                    tensorDump: &dump
                )
                samples = result?.audio ?? []
            } catch {
                errorText = "\(error) [stage=\(models.lastVendedStage)]"
            }
            let synthSec = Date().timeIntervalSince(t0)
            let audioSec = Double(samples.count) / Double(PipelineConstants.sampleRate)
            let rtf = audioSec > 0 ? synthSec / audioSec : .nan
            let footprint = SynthBench.footprintMB()
            let thermal = ProcessInfo.processInfo.thermalState

            var row: [String: String] = [
                "engine": "coreml",
                "policy": policy.name,
                "i": "\(i)",
                "chars": "\(text.utf16.count)",
                "synth": String(format: "%.3f", synthSec),
                "audio": String(format: "%.3f", audioSec),
                "rtf": String(format: "%.3f", rtf),
                "thermal": "\(thermal.rawValue)",
                "footprintMB": "\(footprint)",
                "battery": String(format: "%.2f", UIDevice.current.batteryLevel),
                "charging": "\(UIDevice.current.batteryState != .unplugged)",
                "lowPower": "\(ProcessInfo.processInfo.isLowPowerModeEnabled)",
                "g2p": String(format: "%.3f", g2pSeconds),
                "tokens": "\(tokenCount)",
                "droppedChars": "\(dropped)",
                "error": errorText,
            ]
            if let r = result {
                // `wallTimeSeconds` is the pipeline's own boundary — token IDs in, PCM out — which is
                // what the upstream iPhone 12 Pro / A17 Pro numbers measure. `synth`/`rtf` above stay
                // comparable with the MLX arm instead, which times G2P in.
                row["pipeline"] = String(format: "%.3f", r.wallTimeSeconds)
                row["rtfPipeline"] = String(format: "%.3f", r.audioDurationSeconds > 0 ? r.wallTimeSeconds / r.audioDurationSeconds : .nan)
                row["bucket"] = "\(r.bucketSeconds)"
                row["frames"] = "\(r.predictedDurationFrames)"
                row["durationModel"] = r.durationModelCacheKey
                row["st_duration"] = String(format: "%.3f", r.timings.durationCoreML)
                row["st_align"] = String(format: "%.3f", r.timings.alignment)
                row["st_matrix"] = String(format: "%.3f", r.timings.matrixOps)
                row["st_f0ntrain"] = String(format: "%.3f", r.timings.f0ntrainCoreML)
                row["st_pad"] = String(format: "%.3f", r.timings.padding)
                row["st_decoderPre"] = String(format: "%.3f", r.timings.decoderPre)
                row["st_hnsf"] = String(format: "%.3f", r.timings.hnsfSwift)
                row["st_generator"] = String(format: "%.3f", r.timings.generatorCoreML)
                row["st_trim"] = String(format: "%.3f", r.timings.trim)
            }
            SpikeLog.shared.record("sentence", row)

            if i < 3, let r = result, !samples.isEmpty {
                logWordTimings(i: i, words: words, owners: owners, result: r)
                // §7.4: the same three sentences as WAVs, next to the CSV, for the listening check.
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let wav = docs.appendingPathComponent("sentence-\(i).wav")
                do {
                    try WavWriter.write(samples: samples, sampleRate: PipelineConstants.sampleRate, to: wav)
                    SpikeLog.shared.record("wav.written", ["i": "\(i)", "file": wav.lastPathComponent, "text": text])
                } catch {
                    SpikeLog.shared.record("wav.failed", ["i": "\(i)", "error": "\(error)"])
                }
                // What this row proves, and what it does not.
                //
                // It does NOT settle 25 ms vs 12.5 ms per duration frame. The executor trims to
                // `round(frames * 2 / f0FrameRate * sampleRate)` (KokoroSynthesisExecutor.swift,
                // stage 9) and `samplesPerDurationFrame` is `sampleRate * 2 / f0FrameRate` — the
                // same formula — so `expectedSamples == actualSamples` by construction for any
                // utterance that fits its bucket. The one thing it does prove is that it *did* fit:
                // `trimLen = min(waveformArray.count, targetLen)`, so a mismatch means the bucket
                // clamped the audio and the run is measuring truncated speech.
                //
                // The constant is settled off-device instead: an energy envelope over the WAV
                // (does the speech fill the whole file, or is the tail silence?) plus
                // spikes/timing_check.py on the per-word `timing` rows, plus listening.
                SpikeLog.shared.record("frames.check", [
                    "i": "\(i)",
                    "proves": "bucket-fit-only-not-the-frame-constant",
                    "frames": "\(r.predictedDurationFrames)",
                    "samplesPerFrame": "\(PipelineConstants.samplesPerDurationFrame)",
                    "expectedSamples": "\(r.predictedDurationFrames * PipelineConstants.samplesPerDurationFrame)",
                    "actualSamples": "\(samples.count)",
                    "bucketSeconds": "\(r.bucketSeconds)",
                    "bucketSamples": "\(r.bucketSeconds * PipelineConstants.sampleRate)",
                    "trimSampleCount": "\(r.trimSampleCount)",
                    "audioDurationSeconds": String(format: "%.3f", r.audioDurationSeconds),
                ])
            }

            progress.iterations = i + 1
            progress.lastRTF = rtf
            progress.lastAudioSeconds = audioSec
            progress.lastSynthSeconds = synthSec
            progress.footprintMB = footprint
            progress.thermal = thermal
            progress.error = errorText
            onProgress(progress)

            if cycle.playbackRate > 0 {
                let sleep = audioSec / cycle.playbackRate - synthSec
                if sleep > 0 { Thread.sleep(forTimeInterval: sleep) }
            }
            i += 1
          }
        }
        SpikeLog.shared.record("bench.stop", ["engine": "coreml", "iterations": "\(i)"])
    }

    /// One `timing` row per Misaki word, folded from the pipeline's per-input-token duration frames.
    ///
    /// `tokenDurationFrames` is aligned with the framed `inputIds` prefix (BOS + phoneme ids + EOS),
    /// so phoneme id *k* is frame entry *k + 1*. Each word's span is the sum over the ids it owns.
    private func logWordTimings(i: Int, words: [MToken], owners: [Int], result: SynthesisResult) {
        let frames = result.tokenDurationFrames
        let secondsPerFrame =
            Double(PipelineConstants.samplesPerDurationFrame) / Double(PipelineConstants.sampleRate)
        // Cumulative frames before phoneme id k, offset by the BOS entry.
        var cumulative = [Int](repeating: 0, count: owners.count + 1)
        cumulative[0] = frames.first ?? 0
        for k in 0..<owners.count {
            cumulative[k + 1] = cumulative[k] + (k + 1 < frames.count ? frames[k + 1] : 0)
        }
        var first = [Int: Int](), last = [Int: Int]()
        for (k, owner) in owners.enumerated() {
            if first[owner] == nil { first[owner] = k }
            last[owner] = k
        }
        for (index, word) in words.enumerated() {
            guard let f = first[index], let l = last[index] else { continue }
            let start = Double(cumulative[f]) * secondsPerFrame
            let end = Double(cumulative[l + 1]) * secondsPerFrame
            SpikeLog.shared.record("timing", [
                "i": "\(i)", "k": "\(index)", "token": word.text,
                "start": String(format: "%.3f", start),
                "end": String(format: "%.3f", end),
                "frames": "\(cumulative[l + 1] - cumulative[f])",
            ])
        }
    }
}
