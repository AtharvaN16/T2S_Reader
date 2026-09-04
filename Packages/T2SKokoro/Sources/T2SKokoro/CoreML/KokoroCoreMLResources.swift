import Foundation
import KokoroPipeline

/// The Core ML Kokoro model files: eight staged inference stages, the voice table, the tokenizer
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
    /// Bucket lengths, in seconds, staged for the decoder and F0Ntrain models.
    public static let buckets = [7, 15]
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
                "The Core ML Kokoro model is not installed (\(name) is missing). "
                    + "Run scripts/fetch-kokoro-coreml.sh --app to install it."
            case .noVoices:
                "The Core ML Kokoro voice table is not installed (no voice files were found). "
                    + "Run scripts/fetch-kokoro-coreml.sh --app to install it."
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
        names += buckets.compactMap { PipelineConstants.tFramesForBucket[$0] }.map { "kokoro_f0ntrain_t\($0)" }
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
            isPrecompiled: stages.values.allSatisfy { $0.pathExtension == "mlmodelc" }
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

    /// Where the files sit when running from the repository rather than an app bundle: the checkout's
    /// `App/Resources/KokoroCoreML`.
    public static var developmentDirectory: URL {
        // This file is <repo>/Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLResources.swift.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "App/Resources/KokoroCoreML", directoryHint: .isDirectory)
    }
}
