import Foundation
import KokoroPipeline

/// The Core ML Kokoro model files: fourteen staged inference stages, the voice table, the tokenizer
/// vocabulary and the harmonic-plus-noise synthesis filter weights, as staged by
/// `scripts/fetch-kokoro-coreml.sh` and consumed by Task 3's engine.
///
/// Deliberately MLX-free, like ``KokoroResources``: availability probes and the app's launch path ask
/// whether the Core ML route can run long before anything decides to load a model.
public enum KokoroCoreMLResources: Sendable {
    /// The upstream `mattmireles/kokoro-coreml` model revision these files were exported from.
    public static let modelRevision = "2e878c6a33c56b40de094ef8237bf15a83d233c5"
    /// The first eight characters of ``modelRevision``.
    public static let revisionPrefix = "2e878c6a"
    /// Bucket lengths, in seconds, staged for the decoder and F0Ntrain models. 3 and 10 since Plan 17
    /// (audit #9): a streamed first piece (48 ids, about 3 s) renders in the 3 s bucket, and a packed
    /// sentence of 8-10 s in the 10 s one rather than padding out the 15 s one. Every weight file is
    /// byte-identical across buckets; only the compute plan differs.
    public static let buckets = [3, 7, 10, 15]
    /// The buckets the engine is ready with: the smallest and the largest, so a cold launch's first
    /// sound waits for eight compute plans (both duration models and these two buckets' three stages
    /// each) rather than fourteen. The streamed first piece of an utterance is about three seconds
    /// and renders in the 3 s bucket; every other piece fits the 15 s one, so nothing rendered
    /// before the 7 s and 10 s buckets land is split or seamed any differently — those two only
    /// save time (`KokoroCoreMLEngine` swaps them in as they arrive).
    public static let readyBuckets = [3, 15]
    /// The buckets loaded after readiness, smallest first.
    public static var laterBuckets: [Int] { buckets.filter { !readyBuckets.contains($0) }.sorted() }
    /// Padded input-token lengths staged for the duration model.
    public static let durationTokenLengths = [128, 256]

    /// A directory (or bundle) that holds every staged model, every voice and both runtime JSON
    /// files, with existence already checked.
    public struct Located: Hashable, Sendable {
        /// Stage name, e.g. `"kokoro_duration_t128"`, to its `.mlpackage` or `.mlmodelc` URL.
        public let stages: [String: URL]
        /// Voice name, e.g. `"af_heart"`, to its `.bin` URL.
        public let voices: [String: URL]
        public let vocab: URL
        public let hnsfWeights: URL
        /// True only when every stage was found as a `.mlmodelc` — Xcode's build-time compile of a
        /// bundled `.mlpackage` — rather than the raw `.mlpackage` this package's development layout
        /// vends.
        public let isPrecompiled: Bool

        public init(stages: [String: URL], voices: [String: URL], vocab: URL, hnsfWeights: URL, isPrecompiled: Bool) {
            self.stages = stages
            self.voices = voices
            self.vocab = vocab
            self.hnsfWeights = hnsfWeights
            self.isPrecompiled = isPrecompiled
        }
    }

    /// Why a bundle or directory cannot serve as the Core ML Kokoro resource location. The payload is
    /// the stage or file name that was first found absent.
    public enum Failure: Error, Hashable, Sendable, LocalizedError {
        case missing(String)
        case noVoices

        public var errorDescription: String? {
            switch self {
            case .missing(let name):
                "The Core ML Kokoro model is not installed (\(name) is missing)."
            case .noVoices:
                "The Core ML Kokoro voice table is not installed (no voice files were found)."
            }
        }
    }

    /// The staged model names, in load order: both duration models, then one F0Ntrain model per
    /// bucket, then decoder-pre and decoder-har-post per bucket. ``locate(in:)`` and
    /// ``locate(inDirectory:)`` check stages in this order, so a directory missing everything always
    /// fails on `kokoro_duration_t128` first.
    public static func stageNames(
        buckets: [Int] = buckets,
        durationTokenLengths: [Int] = durationTokenLengths
    ) -> [String] {
        var names = durationTokenLengths.map { "kokoro_duration_t\($0)" }
        // Two buckets can share one F0Ntrain geometry: each name once, in bucket order.
        var tFrames: [Int] = []
        for bucket in buckets {
            if let t = PipelineConstants.tFramesForBucket[bucket], !tFrames.contains(t) { tFrames.append(t) }
        }
        names += tFrames.map { "kokoro_f0ntrain_t\($0)" }
        names += buckets.map { "kokoro_decoder_pre_\($0)s" }
        names += buckets.map { "kokoro_decoder_har_post_\($0)s" }
        return names
    }

    /// Looks for every stage as a flat `<name>.mlmodelc` in the bundle root — where Xcode puts a
    /// bundled `.mlpackage` once it has compiled it — then every `*.bin` at the bundle root as a
    /// voice (keyed by file stem), then the two runtime JSON files.
    public static func locate(in bundle: Bundle) -> Result<Located, Failure> {
        var stages: [String: URL] = [:]
        for name in stageNames() {
            guard let url = bundle.url(forResource: name, withExtension: "mlmodelc") else {
                return .failure(.missing(name))
            }
            stages[name] = url
        }

        let voiceURLs = bundle.urls(forResourcesWithExtension: "bin", subdirectory: nil) ?? []
        guard !voiceURLs.isEmpty else { return .failure(.noVoices) }
        var voices: [String: URL] = [:]
        for url in voiceURLs {
            voices[url.deletingPathExtension().lastPathComponent] = url
        }

        guard let vocab = bundle.url(forResource: "kokoro-vocab", withExtension: "json") else {
            return .failure(.missing("kokoro-vocab.json"))
        }
        guard let hnsfWeights = bundle.url(forResource: "hnsf_weights", withExtension: "json") else {
            return .failure(.missing("hnsf_weights.json"))
        }

        return .success(Located(
            stages: stages, voices: voices, vocab: vocab, hnsfWeights: hnsfWeights,
            // Always true here: the loop above asks the bundle for `<name>.mlmodelc` and returns
            // `.missing` for anything it does not find, so every stage is compiled by construction.
            // (The directory overload really does have to look; it stages `.mlpackage`.)
            isPrecompiled: true
        ))
    }

    /// Looks for the layout `scripts/fetch-kokoro-coreml.sh --app` stages under `directory`:
    /// `coreml/<stage>.mlpackage`, `voices/*.bin` and the two `runtime/*.json` files. This is the
    /// layout ``developmentDirectory`` and the package's own tests use — never precompiled.
    public static func locate(inDirectory directory: URL) -> Result<Located, Failure> {
        let fileManager = FileManager.default
        let coreml = directory.appending(path: "coreml", directoryHint: .isDirectory)

        var stages: [String: URL] = [:]
        for name in stageNames() {
            let url = coreml.appending(path: "\(name).mlpackage", directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return .failure(.missing(name)) }
            stages[name] = url
        }

        let voicesDirectory = directory.appending(path: "voices", directoryHint: .isDirectory)
        let voiceURLs = (try? fileManager.contentsOfDirectory(at: voicesDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "bin" } ?? []
        guard !voiceURLs.isEmpty else { return .failure(.noVoices) }
        var voices: [String: URL] = [:]
        for url in voiceURLs {
            voices[url.deletingPathExtension().lastPathComponent] = url
        }

        let runtime = directory.appending(path: "runtime", directoryHint: .isDirectory)
        let vocab = runtime.appending(path: "kokoro-vocab.json")
        guard fileManager.fileExists(atPath: vocab.path(percentEncoded: false)) else {
            return .failure(.missing("kokoro-vocab.json"))
        }
        let hnsfWeights = runtime.appending(path: "hnsf_weights.json")
        guard fileManager.fileExists(atPath: hnsfWeights.path(percentEncoded: false)) else {
            return .failure(.missing("hnsf_weights.json"))
        }

        return .success(Located(
            stages: stages, voices: voices, vocab: vocab, hnsfWeights: hnsfWeights,
            isPrecompiled: stages.values.allSatisfy { $0.pathExtension == "mlmodelc" }
        ))
    }

    /// Looks for the layout `KokoroCoreMLInstall` leaves under a revision directory: the compiled
    /// stages as `compiled/<name>.mlmodelc`, the voices as `staging/voices/*.bin` and the runtime
    /// JSON under `staging/runtime/`. Always precompiled; the installer removes the sources.
    public static func locate(installedIn root: URL) -> Result<Located, Failure> {
        let fileManager = FileManager.default
        let compiled = root.appending(path: "compiled", directoryHint: .isDirectory)
        let staging = root.appending(path: "staging", directoryHint: .isDirectory)

        var stages: [String: URL] = [:]
        for name in stageNames() {
            let url = compiled.appending(path: "\(name).mlmodelc", directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return .failure(.missing(name)) }
            stages[name] = url
        }

        let voicesDirectory = staging.appending(path: "voices", directoryHint: .isDirectory)
        let voiceURLs = (try? fileManager.contentsOfDirectory(at: voicesDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "bin" } ?? []
        guard !voiceURLs.isEmpty else { return .failure(.noVoices) }
        var voices: [String: URL] = [:]
        for url in voiceURLs {
            voices[url.deletingPathExtension().lastPathComponent] = url
        }

        let runtime = staging.appending(path: "runtime", directoryHint: .isDirectory)
        let vocab = runtime.appending(path: "kokoro-vocab.json")
        guard fileManager.fileExists(atPath: vocab.path(percentEncoded: false)) else {
            return .failure(.missing("kokoro-vocab.json"))
        }
        let hnsfWeights = runtime.appending(path: "hnsf_weights.json")
        guard fileManager.fileExists(atPath: hnsfWeights.path(percentEncoded: false)) else {
            return .failure(.missing("hnsf_weights.json"))
        }

        return .success(Located(stages: stages, voices: voices, vocab: vocab, hnsfWeights: hnsfWeights, isPrecompiled: true))
    }

    /// Where the files sit when running from the repository rather than an app bundle: the checkout's
    /// `App/Resources/KokoroCoreML`.
    public static var developmentDirectory: URL {
        // This file is <repo>/Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLResources.swift.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "App/Resources/KokoroCoreML", directoryHint: .isDirectory)
    }
}
