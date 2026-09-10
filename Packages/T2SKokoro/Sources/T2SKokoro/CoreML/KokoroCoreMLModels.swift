import CoreML
import Foundation
import KokoroPipeline

/// The pipeline's synthesis result, under a name the engine can spell.
///
/// `SynthesisResult` is declared by both `T2SCore` and `KokoroPipeline`, and the module name does not
/// disambiguate the second — `KokoroPipeline` is a class inside that module as well as the module
/// itself. This file does not import `T2SCore`, so the bare name resolves here.
typealias KokoroPipelineResult = SynthesisResult

/// The staged Core ML stages — fourteen since Plan 17's buckets — loaded and vended to `executeKokoroSynthesis`.
///
/// Ported from the Plan 0 Task 8 spike's `CoreMLModelBundle`
/// (`spikes/SpikeHarness/SpikeHarness/CoreMLBench.swift`) with its policy matrix collapsed to the one
/// policy §7.3 chose: every stage on `.cpuOnly`. On an A13 that is RTF 0.18 in 119 MB, where the
/// GPU-assisted policy is twice as slow and wants 1.2 GB
/// (`spikes/findings/2026-09-04-pre-a14-runtime.md`).
///
/// Every staged bucket and duration size is vended, because the executor's own `selectBucket` and
/// `KokoroPipeline.selectDurationChoice` do the picking and both take what this provider offers.
///
/// Neither this type nor `MLModel` is `Sendable`: an instance lives inside ``KokoroCoreMLEngine`` and
/// never leaves it.
final class KokoroCoreMLModels: KokoroModelProvider {
    /// Largest staged duration model. The caller pads `inputIds` to this and the executor copies only
    /// the prefix the model it chose actually needs.
    static let maxDurationTokenLength = KokoroCoreMLResources.durationTokenLengths.reduce(0, max)

    private let durationModels: [Int: MLModel]      // padded token length -> model
    private let f0ntrainModels: [Int: MLModel]      // T frames -> model
    private let decoderPreModels: [Int: MLModel]    // bucket seconds -> model
    private let generatorModels: [Int: MLModel]     // bucket seconds -> model
    private let choices: [DurationModelChoice]
    private let buckets: [Int]

    /// Compiles every staged `.mlpackage` and hands back the compiled URLs, or passes an already
    /// compiled staging straight through.
    ///
    /// The first of a load's two asynchronous steps (``loadStages(_:)`` is the second), kept apart
    /// from the model objects so ``KokoroCoreMLEngine`` can share each step between concurrent
    /// renders through one `Task` and re-check for a finished load after each suspension: the
    /// stages are compiled and loaded once however many renders ask at the same time.
    ///
    /// `async` because the only non-deprecated `MLModel.compileModel` is the asynchronous one. The
    /// app bundle needs no compile at all — Xcode runs `coremlc` at build time, which is what
    /// ``KokoroCoreMLResources/Located/isPrecompiled`` reports — but the development layout this
    /// package's tests read stages `.mlpackage` directories, so those are compiled here into the
    /// per-process temporary directory `compileModel` returns.
    static func compileStages(_ resources: KokoroCoreMLResources.Located) async throws -> [String: URL] {
        guard !resources.isPrecompiled else { return resources.stages }
        var compiled: [String: URL] = [:]
        for name in KokoroCoreMLResources.stageNames() {
            guard let staged = resources.stages[name] else { throw KokoroCoreMLResources.Failure.missing(name) }
            compiled[name] = try await MLModel.compileModel(at: staged)
        }
        return compiled
    }

    /// Every stage's model, loaded a few at a time from the compiled URLs ``compileStages(_:)`` returned.
    ///
    /// `MLModel.load` builds the compute plan, and that is where a slow first load goes: 206 s on an
    /// A13's first launch after install, 3-5 s on every later one (§7.3) — one stage after another,
    /// until Plan 17 (audit §4.1). The builds are independent, so the warm-up now pays for the
    /// longest few, not the sum. ``loadWindow`` builds at once: the ceiling on speed is the core
    /// count, and the window is what bounds the peak footprint while every plan is under
    /// construction — the audit asked for that peak to be measured on an A13, and it has not been.
    /// `MLModel` is not `Sendable`: ``LoadedStages`` carries them out of the group unchecked, under
    /// the rule the engine already keeps — nothing touches a model until every load has returned
    /// and the set is on the engine's actor.
    static func loadStages(_ compiled: [String: URL],
                           onProgress: (@Sendable (_ loaded: Int, _ total: Int) -> Void)? = nil) async throws -> LoadedStages {
        var models: [String: MLModel] = [:]
        let names = KokoroCoreMLResources.stageNames()
        var pending = names[...]
        try await withThrowingTaskGroup(of: StageLoad.self) { group in
            func addNext() throws {
                guard let name = pending.popFirst() else { return }
                guard let url = compiled[name] else { throw KokoroCoreMLResources.Failure.missing(name) }
                group.addTask {
                    let configuration = MLModelConfiguration()
                    configuration.computeUnits = .cpuOnly
                    return StageLoad(name: name, model: try await MLModel.load(contentsOf: url, configuration: configuration))
                }
            }
            for _ in 0 ..< loadWindow { try addNext() }
            for try await load in group {
                models[load.name] = load.model
                onProgress?(models.count, names.count)                   // the warm-up's veil counts stages by this
                try addNext()
            }
        }
        return LoadedStages(models: models, urls: compiled)
    }

    /// How many compute plans build at once.
    static let loadWindow = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))

    /// The stages as ``loadStages(_:)`` returns them; see there for why this is `@unchecked`.
    struct LoadedStages: @unchecked Sendable {
        let models: [String: MLModel]
        let urls: [String: URL]
    }

    private struct StageLoad: @unchecked Sendable {
        let name: String
        let model: MLModel
    }

    /// Vends the loaded stages. Synchronous on purpose: it runs to completion on the engine's actor,
    /// so no second render can arrive between the first one's decision to load and the loaded stages
    /// being there.
    init(stages: LoadedStages) throws {
        func load(_ name: String) throws -> (model: MLModel, url: URL) {
            guard let model = stages.models[name], let url = stages.urls[name] else {
                throw KokoroCoreMLResources.Failure.missing(name)
            }
            return (model, url)
        }

        var durations: [Int: MLModel] = [:]
        var durationChoices: [DurationModelChoice] = []
        // Ascending, because `selectDurationChoice` returns the first padded choice that fits and
        // upstream sorts its choices the same way — the smallest model that holds the tokens wins.
        for tokens in KokoroCoreMLResources.durationTokenLengths.sorted() {
            let stage = try load("kokoro_duration_t\(tokens)")
            durations[tokens] = stage.model
            durationChoices.append(DurationModelChoice(
                cacheKey: "padded_t\(tokens)",
                tokenLength: tokens,
                packageURL: stage.url,
                requiresAttentionMask: true,
                allowsPadding: true
            ))
        }
        durationModels = durations
        choices = durationChoices

        let staged = KokoroCoreMLResources.buckets.sorted()
        var f0ntrain: [Int: MLModel] = [:]
        var decoderPre: [Int: MLModel] = [:]
        var generator: [Int: MLModel] = [:]
        for seconds in staged {
            guard let tFrames = PipelineConstants.tFramesForBucket[seconds] else {
                throw KokoroCoreMLResources.Failure.missing("kokoro_f0ntrain for the \(seconds)s bucket")
            }
            // Two buckets can share one F0Ntrain geometry; load each only once.
            if f0ntrain[tFrames] == nil {
                f0ntrain[tFrames] = try load("kokoro_f0ntrain_t\(tFrames)").model
            }
            decoderPre[seconds] = try load("kokoro_decoder_pre_\(seconds)s").model
            generator[seconds] = try load("kokoro_decoder_har_post_\(seconds)s").model
        }
        f0ntrainModels = f0ntrain
        decoderPreModels = decoderPre
        generatorModels = generator
        buckets = staged
    }

    func durationModelChoices() -> [DurationModelChoice] { choices }

    func availableBucketSeconds() -> [Int] { buckets }

    func durationModel(choice: DurationModelChoice) throws -> MLModel {
        guard let model = durationModels[choice.tokenLength] else {
            throw KokoroCoreMLResources.Failure.missing("kokoro_duration_t\(choice.tokenLength)")
        }
        return model
    }

    func f0ntrainModel(tFrames: Int) throws -> MLModel {
        guard let model = f0ntrainModels[tFrames] else {
            throw KokoroCoreMLResources.Failure.missing("kokoro_f0ntrain_t\(tFrames)")
        }
        return model
    }

    func decoderPreModel(bucketSec: Int) throws -> MLModel {
        guard let model = decoderPreModels[bucketSec] else {
            throw KokoroCoreMLResources.Failure.missing("kokoro_decoder_pre_\(bucketSec)s")
        }
        return model
    }

    func generatorModel(bucketSec: Int) throws -> MLModel {
        guard let model = generatorModels[bucketSec] else {
            throw KokoroCoreMLResources.Failure.missing("kokoro_decoder_har_post_\(bucketSec)s")
        }
        return model
    }
}
