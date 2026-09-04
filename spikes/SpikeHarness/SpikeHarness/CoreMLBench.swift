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

    static func named(_ name: String) -> CoreMLStagePolicy {
        name == "cpuOnly" ? .cpuOnly : .gistDefault
    }
}

/// Serves the Xcode-precompiled `.mlmodelc` bundles to `executeKokoroSynthesis`.
///
/// Mirrors `BundleModelCache` in the upstream repo's `ios-bench/Sources/BenchApp.swift`: Xcode runs
/// coremlc at build time, so loading is a plain `MLModel(contentsOf:)` with no on-device compile.
/// Only the 15-second bucket and the 256-token duration model are staged (see
/// scripts/fetch-kokoro-coreml.sh), so there is nothing to evict.
final class CoreMLModelBundle: KokoroModelProvider {
    static let bucketSeconds = 15
    static let durationTokenLength = 256

    private let durationModel: MLModel
    private let f0ntrain: MLModel
    private let decoderPre: MLModel
    private let generator: MLModel
    let choice: DurationModelChoice
    /// Best in-process hint for which stage a first-predict failure came from.
    private(set) var lastVendedStage = ""

    init(policy: CoreMLStagePolicy) throws {
        func config(_ units: MLComputeUnits) -> MLModelConfiguration {
            let c = MLModelConfiguration()
            c.computeUnits = units
            return c
        }
        // One row per stage: `MLModel(contentsOf:)` builds the compute plan (ANE compile, MPSGraph
        // specialization), and on older silicon that is where the minutes go. Without these rows a
        // slow load is indistinguishable from a hang.
        func load(_ name: String, _ units: MLComputeUnits) throws -> MLModel {
            let url = try Self.compiledURL(name)
            let t = Date()
            let model = try MLModel(contentsOf: url, configuration: config(units))
            SpikeLog.shared.record("model.stage", [
                "name": name, "units": "\(units.rawValue)",
                "seconds": String(format: "%.2f", Date().timeIntervalSince(t)),
                "footprintMB": "\(SynthBench.footprintMB())",
            ])
            return model
        }
        let durationURL = try Self.compiledURL("kokoro_duration_t\(Self.durationTokenLength)")
        durationModel = try load("kokoro_duration_t\(Self.durationTokenLength)", policy.duration)
        f0ntrain = try load("kokoro_f0ntrain_t600", policy.f0ntrain)
        decoderPre = try load("kokoro_decoder_pre_\(Self.bucketSeconds)s", policy.decoderPre)
        generator = try load("kokoro_decoder_har_post_\(Self.bucketSeconds)s", policy.generator)
        choice = DurationModelChoice(
            cacheKey: "padded_t\(Self.durationTokenLength)",
            tokenLength: Self.durationTokenLength,
            packageURL: durationURL,
            requiresAttentionMask: true,
            allowsPadding: true
        )
    }

    private static func compiledURL(_ name: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw CoreMLBench.Failure.missingModel("\(name).mlmodelc")
        }
        return url
    }

    func durationModelChoices() -> [DurationModelChoice] { [choice] }
    func availableBucketSeconds() -> [Int] { [Self.bucketSeconds] }
    func durationModel(choice: DurationModelChoice) throws -> MLModel {
        lastVendedStage = "duration"; return durationModel
    }
    func f0ntrainModel(tFrames: Int) throws -> MLModel {
        lastVendedStage = "f0ntrain"; return f0ntrain
    }
    func decoderPreModel(bucketSec: Int) throws -> MLModel {
        lastVendedStage = "decoderPre"; return decoderPre
    }
    func generatorModel(bucketSec: Int) throws -> MLModel {
        lastVendedStage = "generator"; return generator
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

    init(voiceName: String = "af_heart", policy: CoreMLStagePolicy = .gistDefault) throws {
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
        models = try CoreMLModelBundle(policy: policy)
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
            "bucket": "\(CoreMLModelBundle.bucketSeconds)",
            "durationTokens": "\(CoreMLModelBundle.durationTokenLength)",
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
                guard framed.count <= CoreMLModelBundle.durationTokenLength else {
                    throw Failure.badResource(
                        "sentence is \(framed.count) tokens, over the \(CoreMLModelBundle.durationTokenLength)-token duration model")
                }
                // The duration model is static-shape: pad ids with the boundary token and the mask
                // with 0 to the model's token length. `buildDurationInput` copies only what the
                // caller supplies into an MLMultiArray it does not zero, so padding here is required.
                let pad = CoreMLModelBundle.durationTokenLength - framed.count
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
                // The frame→seconds gate for Task 8b: `PipelineConstants` says 600 samples (25 ms at
                // 24 kHz) per duration frame, the ONNX community recipe says 12.5 ms. Log both sides
                // so the answer comes from the WAV, not from a constant.
                SpikeLog.shared.record("frames.check", [
                    "i": "\(i)",
                    "frames": "\(r.predictedDurationFrames)",
                    "samplesPerFrame": "\(PipelineConstants.samplesPerDurationFrame)",
                    "expectedSamples": "\(r.predictedDurationFrames * PipelineConstants.samplesPerDurationFrame)",
                    "actualSamples": "\(samples.count)",
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
