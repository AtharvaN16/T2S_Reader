import Dispatch
import Foundation
import KokoroPipeline
import MisakiSwift
import MLX
// `MToken` — what `EnglishG2P.phonemize` hands back — is declared here, not in MisakiSwift.
import MLXUtilsLibrary
import T2SAudio
import T2SCore

/// The Core ML arm of spec §3: MisakiSwift's G2P in front of `mattmireles/kokoro-coreml`'s staged
/// pipeline, every stage on the CPU.
///
/// The runtime the §7.3 spike chose. It is the only one that runs at all on a pre-A14 phone — MLX's
/// Kokoro traps in Metal's steel GEMM kernels there — and on an A13 it renders at RTF 0.18 in 119 MB
/// (`spikes/findings/2026-09-04-pre-a14-runtime.md`), so it is the baseline everywhere.
///
/// An actor because eight `MLModel`s, a voice table and a G2P are mutable state that must be touched
/// one utterance at a time, and because none of those types is `Sendable` — they never leave here.
public actor KokoroCoreMLEngine: SynthesisEngine {
    public static let runtime = "coreml-cpu"
    public static let g2p = "misaki1.0.6"

    /// The render-key identity (spec §5): the model revision these stages were exported from, the
    /// runtime and the G2P version. Any of the three changing changes the audio, so all three are in
    /// the key.
    public static let identity = "kokoro-coreml-\(KokoroCoreMLResources.revisionPrefix)-\(g2p)"

    public nonisolated let engineID = KokoroCoreMLEngine.identity

    /// The most input ids one pipeline call may carry.
    ///
    /// The app's segmenter allows 300 characters of source — 50 to 60 words, up to about 20 seconds
    /// of speech — but the duration model's largest staged input is 256 tokens, and past that the
    /// bucket selector silently falls back to the 15-second bucket and the executor clamps the audio
    /// to it: truncated speech with no signal. So a long utterance is split into consecutive pieces
    /// instead. 176 ids frame to 178, well inside 256, and speak for about 13 seconds, inside the
    /// 15-second bucket. Most sentences are one piece; the seam is a prosody nit on the longest ones.
    static let maxPieceTokenCount = 176

    /// Misaki's marker for a word it could not transcribe. Passed to `EnglishG2P` explicitly so
    /// ``phonemeWalk(_:)`` provably reproduces the string `phonemize` returns.
    static let unknownPhoneme = "❓"

    private let resources: KokoroCoreMLResources.Located
    private var loaded: Loaded?
    /// The stage compile in flight, if one is. See ``compiledStages()`` for why it is shared.
    private var compiling: Task<[String: URL], Error>?
    /// How many times this engine has begun loading its stages. Internal for one test: "loaded once"
    /// and "compiled and loaded twice" differ only in this number and several minutes of Core ML.
    private(set) var loadCount = 0
    /// One per voice: the style table is the voice, and the vocabulary beside it is 114 entries.
    private var tokenizers: [String: KokoroTokenizer] = [:]
    private var americanG2P: EnglishG2P?
    private var britishG2P: EnglishG2P?

    /// Core ML prediction blocks its thread for seconds at a time. On the cooperative pool that would
    /// starve every other actor in the app, so this actor runs on a queue of its own instead.
    private let queue = DispatchSerialQueue(label: "com.t2s.reader.kokoro-coreml", qos: .userInitiated)
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// The loaded stages and the one piece of the vocoder that stayed in Swift, isolated to the actor
    /// along with them.
    private struct Loaded {
        let models: KokoroCoreMLModels
        let linearWeights: [Float]
        let linearBias: Float
    }

    public init(resources: KokoroCoreMLResources.Located) {
        self.resources = resources
    }

    /// Loads the eight stages, compiling them first when the staging is not precompiled, and the
    /// vocoder weights. `synthesize` calls it lazily on first use; a caller that would rather pay the
    /// seconds before playback starts can call it itself.
    public func preload() async throws {
        _ = try await load()
    }

    @discardableResult
    private func load() async throws -> Loaded {
        if let loaded { return loaded }
        // hn-NSF's `l_linear` weights: the one piece of the vocoder that stayed in Swift.
        struct HnsfWeights: Decodable {
            let linear_weights: [Float]
            let linear_bias: Float
        }
        do {
            let compiled = try await compiledStages()
            // The compile is this function's only suspension, and the actor is released across it,
            // so a render that arrived meanwhile may have finished the whole load. Building a second
            // set of eight `MLModel`s would pay for eight more compute plans and hold two copies of
            // the 119 MB (§7.3) until the first was dropped.
            if let loaded { return loaded }
            try Task.checkCancellation()

            let weights = try JSONDecoder().decode(HnsfWeights.self, from: Data(contentsOf: resources.hnsfWeights))
            // Synchronous, so from here to the assignment the actor is never released: no other
            // render can observe this engine mid-load.
            let loaded = Loaded(models: try KokoroCoreMLModels(compiledStages: compiled),
                                linearWeights: weights.linear_weights,
                                linearBias: weights.linear_bias)
            self.loaded = loaded
            return loaded
        } catch is CancellationError {
            // A render cancelled while the stages were compiling is not an engine failure. Wrapping
            // it would surface a stopped utterance as 200 ms of silence and a logged error instead
            // of the scheduler simply dropping it.
            throw CancellationError()
        } catch {
            // Core ML's own error, a missing stage or a malformed weights file — never the request
            // text: this string reaches logs.
            throw KokoroCoreMLError.stageFailed(String(describing: error))
        }
    }

    /// The compiled stage URLs, compiling the `.mlpackage` staging exactly once however many renders
    /// ask at the same time.
    ///
    /// `MLModel.compileModel` is asynchronous, so the actor is released while it runs and `load()`
    /// is reentrant across it. The recommended app wiring — `preload()` off the playback path, a
    /// render on play — is exactly the pattern that arrives twice: without sharing the one task both
    /// would compile and load a full set of eight stages, doubling the compute-plan build (206 s on
    /// an A13's first launch) and, briefly, the footprint. Sharing a `Task` is what makes the two
    /// callers wait on the same work; URLs are the only part of a load that may cross the suspension,
    /// which is why the compile is split out of ``KokoroCoreMLModels`` at all.
    private func compiledStages() async throws -> [String: URL] {
        if let compiling { return try await compiling.value }
        loadCount += 1
        // Nothing to compile: Xcode ran `coremlc` at build time, so on the app's own staging this
        // function never suspends and `load()` cannot be reentered at all.
        guard !resources.isPrecompiled else { return resources.stages }

        let task = Task { [resources] in try await KokoroCoreMLModels.compileStages(resources) }
        compiling = task
        do {
            return try await task.value
        } catch {
            // A failed compile must not poison the engine: clearing the task lets the next render
            // try again rather than inherit this failure for the life of the app.
            compiling = nil
            throw error
        }
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> T2SCore.SynthesisResult {
        // Both checks come before the load, so a misrouted request costs nothing and the tests that
        // pin them need no model.
        guard let id = KokoroVoiceID(rawValue: request.voiceID), id.engineID == engineID else {
            throw KokoroCoreMLError.voiceNotForThisEngine(request.voiceID)
        }
        guard !request.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SynthesisError.failed("nothing to speak")
        }
        // The last chance to leave cheaply. The scheduler cancels pending renders on stop, and this
        // actor's queue is serial: without this, a cancelled render would still compile eight stages
        // and synthesize for seconds while the next real one waited behind it.
        try Task.checkCancellation()
        // The staged voice table is already in hand, so a voice this staging does not have costs
        // nothing either.
        guard let voiceURL = resources.voices[id.voice] else {
            throw KokoroCoreMLError.unknownVoice(id.voice)
        }

        let loaded = try await load()
        let tokenizer = try tokenizer(voice: id.voice, url: voiceURL)
        // The staged voice names: `a*` are the American voices, `b*` the British ones.
        let words = MLX.Device.withDefaultDevice(.cpu) {
            g2p(british: id.voice.hasPrefix("b")).phonemize(text: request.spoken).1
        }
        let (phonemes, ownersByCharacter) = Self.phonemeWalk(words)
        let tokenization = tokenizer.tokenize(phonemes: phonemes, ownersByCharacter: ownersByCharacter)

        var samples: [Float] = []
        var folds: [KokoroCoreMLTimingFold.Piece] = []
        for piece in try Self.pieces(ids: tokenization.ids, owners: tokenization.owners, words: words) {
            try Task.checkCancellation()
            let rendered = try render(piece, tokenizer: tokenizer, loaded: loaded)
            folds.append(KokoroCoreMLTimingFold.Piece(
                owners: piece.owners,
                frames: rendered.tokenDurationFrames,
                offsetSeconds: Double(samples.count) / Double(PipelineConstants.sampleRate)
            ))
            samples += rendered.audio
        }

        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { throw KokoroCoreMLError.emptyAudio }
        let audio = PCMAudio(sampleRate: Double(PipelineConstants.sampleRate), samples: samples)
        let timed = KokoroCoreMLTimingFold.timedTokens(
            words.map { KokoroToken(text: $0.text, whitespace: $0.whitespace, start: nil, end: nil) },
            pieces: folds
        )
        return T2SCore.SynthesisResult(
            audio: audio,
            wordTimings: KokoroTokenTimingMapper.map(timed, spoken: request.spoken, duration: audio.duration)
        )
    }

    /// One pipeline call. The duration models are static-shape, so the framed ids are padded with the
    /// boundary token and the mask with zeroes: `buildDurationInput` copies only what it is given
    /// into an `MLMultiArray` it does not zero. Padding to the *largest* staged model and letting
    /// `selectDurationChoice` pick the smallest that fits is safe either way — it copies a prefix of
    /// the padded ids, and the mask's zeroes tell it where the real tokens end.
    private func render(_ piece: Piece, tokenizer: KokoroTokenizer, loaded: Loaded) throws -> KokoroPipelineResult {
        let framed = [KokoroTokenizer.boundary] + piece.ids + [KokoroTokenizer.boundary]
        let padding = KokoroCoreMLModels.maxDurationTokenLength - framed.count
        // ``maxPieceTokenCount`` (176 + 2 frame tokens) is chosen to fit `maxDurationTokenLength`
        // (256, the largest staged duration model). The two constants are coupled by hand, so if one
        // ever moves without the other, refuse the piece rather than build a negative-length pad.
        guard padding >= 0 else { throw KokoroCoreMLError.tooManyTokens(framed.count) }
        let result: KokoroPipelineResult
        do {
            var tensorDump: TensorDumpWriter?
            result = try executeKokoroSynthesis(
                request: KokoroSynthesisRequest(
                    inputIds: framed + Array(repeating: KokoroTokenizer.boundary, count: padding),
                    attentionMask: Array(repeating: 1, count: framed.count)
                        + Array(repeating: 0, count: padding),
                    refS: tokenizer.refS(phonemeUTF16Count: piece.phonemeUTF16Count),
                    speed: 1.0
                ),
                modelProvider: loaded.models,
                linearWeights: loaded.linearWeights,
                linearBias: loaded.linearBias,
                tensorDump: &tensorDump
            )
        } catch {
            // The pipeline's own error and never the request text: this string reaches logs.
            throw KokoroCoreMLError.stageFailed(String(describing: error))
        }

        // `selectBucket` falls back to the largest bucket rather than failing, and stage 9 then trims
        // to `min(waveform.count, targetLen)` — so a piece that predicts more speech than its bucket
        // holds comes back clipped, with nothing to say so. Spec §6 would far rather the utterance
        // fail and be filled with 200 ms of silence than have the reader lose the end of a sentence.
        guard result.predictedDurationFrames * PipelineConstants.samplesPerDurationFrame
            <= result.bucketSeconds * PipelineConstants.sampleRate
        else {
            throw KokoroCoreMLError.audioTruncated(
                predictedSeconds: Double(result.predictedDurationFrames) * KokoroCoreMLTimingFold.secondsPerFrame,
                bucketSeconds: result.bucketSeconds
            )
        }
        return result
    }

    private func tokenizer(voice: String, url: URL) throws -> KokoroTokenizer {
        if let cached = tokenizers[voice] { return cached }
        let tokenizer = try KokoroTokenizer(vocabURL: resources.vocab, voiceURL: url)
        tokenizers[voice] = tokenizer
        return tokenizer
    }

    /// The G2P for a language, built once and kept.
    ///
    /// MisakiSwift's out-of-lexicon fallback is a BART network on MLX, whose GEMMs are exactly what a
    /// pre-A14 GPU cannot run — so both the construction and every `phonemize` call are wrapped in
    /// `MLX.Device.withDefaultDevice(.cpu)`, which is a task-local. Deliberately *not*
    /// `MLX.Device.setDefault`: that is process-global, and the MLX Kokoro engine is wired beside this
    /// one in the app, where pinning the process to the CPU would cripple it (RTF 15).
    private func g2p(british: Bool) -> EnglishG2P {
        if let cached = british ? britishG2P : americanG2P { return cached }
        let g2p = MLX.Device.withDefaultDevice(.cpu) { EnglishG2P(british: british, unk: Self.unknownPhoneme) }
        if british { britishG2P = g2p } else { americanG2P = g2p }
        return g2p
    }

    // MARK: Tokens

    /// One synthesis call's worth of input ids, cut at Misaki-token boundaries.
    struct Piece {
        var ids: [Int32] = []
        /// One entry per id: the Misaki token that contributed it, or ``KokoroCoreMLTimingFold/noOwner``.
        var owners: [Int] = []
        /// The UTF-16 length of the phonemized text of every Misaki token this piece covers, which is
        /// what `KokoroTokenizer.refS` picks a voice row with. The pieces tile the token list, so for
        /// a one-piece utterance this is exactly the whole phonemized string's length — the same
        /// number the §7.3 spike measured with.
        var phonemeUTF16Count = 0
    }

    /// The phonemized text and, for each of its `Character`s, the index of the Misaki token that
    /// contributed it — or ``KokoroCoreMLTimingFold/noOwner`` for the whitespace that follows a token.
    ///
    /// `EnglishG2P.phonemize` builds its returned string as
    /// `tokens.map { ($0.phonemes ?? unk) + $0.whitespace }.joined()`, so this walk reproduces it
    /// exactly. It is rebuilt here rather than taken from `phonemize` because
    /// `KokoroTokenizer.tokenize` requires one owner per `Character` and says so with a precondition:
    /// counting each piece's characters as it is appended is the only way to count them the way the
    /// joined string does, whatever the pieces do to each other's grapheme clusters at the seam.
    private static func phonemeWalk(_ words: [MToken]) -> (phonemes: String, ownersByCharacter: [Int]) {
        var phonemes = ""
        var ownersByCharacter: [Int] = []
        var counted = 0

        func append(_ text: String, owner: Int) {
            phonemes += text
            let grown = phonemes.count
            ownersByCharacter += repeatElement(owner, count: grown - counted)
            counted = grown
        }

        for (index, word) in words.enumerated() {
            append(word.phonemes ?? unknownPhoneme, owner: index)
            append(word.whitespace, owner: KokoroCoreMLTimingFold.noOwner)
        }
        return (phonemes, ownersByCharacter)
    }

    /// Cuts the utterance's ids into consecutive pieces of at most ``maxPieceTokenCount`` ids,
    /// greedily and only between Misaki tokens: a token whose ids would push the current piece over
    /// the cap starts the next one, and the whitespace ids after a token stay with it.
    ///
    /// Internal rather than private so the cut can be tested on synthetic ids, on a machine with no
    /// model files: end to end this rule is only visible in an utterance long enough to need two
    /// pipeline calls, which is a minute of Core ML per run.
    static func pieces(ids: [Int32], owners: [Int], words: [MToken]) throws -> [Piece] {
        // The ids of one Misaki token plus the whitespace that follows it: the smallest unit a piece
        // boundary may fall between.
        var groups: [(token: Int, ids: [Int32], owners: [Int])] = []
        for (id, owner) in zip(ids, owners) {
            if owner != KokoroCoreMLTimingFold.noOwner, groups.last?.token != owner {
                groups.append((owner, [], []))
            } else if groups.isEmpty {
                // Whitespace before the first surviving token; it leads the first group.
                groups.append((0, [], []))
            }
            groups[groups.count - 1].ids.append(id)
            groups[groups.count - 1].owners.append(owner)
        }

        var packed: [[(token: Int, ids: [Int32], owners: [Int])]] = []
        var current: [(token: Int, ids: [Int32], owners: [Int])] = []
        var currentCount = 0
        for group in groups {
            guard group.ids.count <= maxPieceTokenCount else {
                // One word longer than a whole pipeline input. Nothing to split it at.
                throw KokoroCoreMLError.tooManyTokens(group.ids.count)
            }
            if currentCount + group.ids.count > maxPieceTokenCount, !current.isEmpty {
                packed.append(current)
                current = []
                currentCount = 0
            }
            current.append(group)
            currentCount += group.ids.count
        }
        if !current.isEmpty { packed.append(current) }

        // The pieces tile the Misaki token list: every token's phonemized length is charged to
        // exactly one piece, including the tokens that survived the vocabulary with no id at all, so
        // the one-piece case reproduces the whole string's length.
        var pieces: [Piece] = []
        var firstToken = 0
        for (index, groups) in packed.enumerated() {
            let lastToken = index == packed.count - 1
                ? max(firstToken, words.count - 1)
                : (groups.last?.token ?? firstToken)
            var piece = Piece()
            for group in groups {
                piece.ids += group.ids
                piece.owners += group.owners
            }
            piece.phonemeUTF16Count = (firstToken ... lastToken).reduce(0) {
                $0 + ((words[$1].phonemes ?? unknownPhoneme) + words[$1].whitespace).utf16.count
            }
            pieces.append(piece)
            firstToken = lastToken + 1
        }
        return pieces
    }
}

public enum KokoroCoreMLError: Error, Equatable, Sendable, LocalizedError {
    /// The request's voice ID is not a `kokoro:` route for this staging.
    case voiceNotForThisEngine(String)
    case unknownVoice(String)
    /// More ids than a pipeline input holds: normally one Misaki token that phonemized past the cap,
    /// so there is no boundary to split it at, and — if the chunker's cap is ever raised out of step
    /// with the duration models — a whole framed piece. The payload is the offending id count.
    case tooManyTokens(Int)
    /// A stage failed to compile, to load or to predict. The payload describes the underlying error
    /// and never the spoken text.
    case stageFailed(String)
    case emptyAudio
    /// The pipeline predicted more speech than its largest bucket holds and clipped the audio to fit,
    /// so what it returned is not the whole passage.
    case audioTruncated(predictedSeconds: Double, bucketSeconds: Int)

    public var errorDescription: String? {
        switch self {
        case .voiceNotForThisEngine:
            "That voice belongs to a different version of the on-device voice."
        case .unknownVoice(let voice):
            "The on-device voice \"\(voice)\" is not installed."
        case .tooManyTokens:
            "The on-device voice could not pronounce a word in this passage."
        case .stageFailed:
            "The on-device voice could not speak this passage."
        case .emptyAudio:
            "The on-device voice produced no audio."
        case .audioTruncated:
            "The on-device voice could not fit this passage into one breath."
        }
    }
}
