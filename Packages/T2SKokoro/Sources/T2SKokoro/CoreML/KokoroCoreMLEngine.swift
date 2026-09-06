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
    /// 15-second bucket. Most sentences are one piece; the seam is a prosody nit on the longest ones
    /// — ``pieces(ids:owners:words:)`` cuts at a sentence or clause boundary before the cap when one
    /// is available, and a piece whose predicted audio still overflows its bucket is split and
    /// rendered in two rather than lost to 200 ms of silence
    /// (`spikes/findings/2026-09-05-coreml-audio-quality.md`).
    static let maxPieceTokenCount = 176

    /// Misaki's marker for a word it could not transcribe. Passed to `EnglishG2P` explicitly so
    /// ``phonemeWalk(_:)`` provably reproduces the string `phonemize` returns.
    static let unknownPhoneme = "❓"

    /// The post-processing choices the engine makes on the pipeline's output. Both exist because
    /// the first listen on the iPhone 11 Pro (2026-09-05) heard cut-off words and abrupt joins;
    /// `spikes/findings/2026-09-05-coreml-audio-quality.md` measures each setting and is why
    /// ``default`` chooses values other than this initializer's own (upstream's).
    public struct Options: Sendable, Hashable {
        /// Which punctuation spans are faded to silence after synthesis. Upstream's default silences
        /// every punctuation token's span, quotation marks included; the app ships `.none` — 25 of
        /// 45 zeroed spans measured held ≥10 ms of audible speech, worst case 75 ms at peak 0.75 on
        /// an exclamation mark.
        public var punctuationSuppression: PunctuationSuppression
        /// Whether consecutive pieces of one utterance are joined with a short equal-power crossfade
        /// (`PcmJoiner`, 5 ms) instead of butted together. The app ships `true`: a long sentence cut
        /// at a word boundary and butted to the next piece left an audible seam.
        public var crossfadePieces: Bool

        public init(punctuationSuppression: PunctuationSuppression = .allPunctuation, crossfadePieces: Bool = false) {
            self.punctuationSuppression = punctuationSuppression
            self.crossfadePieces = crossfadePieces
        }

        /// What the app ships with — not this initializer's own defaults, which are upstream's. See
        /// the property docs above and `spikes/findings/2026-09-05-coreml-audio-quality.md`.
        public static let `default` = Options(punctuationSuppression: .none, crossfadePieces: true)
    }

    private let resources: KokoroCoreMLResources.Located
    public private(set) var options: Options
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

    public init(resources: KokoroCoreMLResources.Located, options: Options = .default) {
        self.resources = resources
        self.options = options
    }

    /// Changes the post-processing for every render from here on. Internal, for the audio probe:
    /// it renders one passage under several settings, and a second engine would mean a second copy
    /// of the loaded stages. The app decides its options once, at construction.
    func setOptions(_ options: Options) {
        self.options = options
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

        let pieces = try Self.pieces(ids: tokenization.ids, owners: tokenization.owners, words: words)
        var samples: [Float] = []
        var folds: [KokoroCoreMLTimingFold.Piece] = []
        for (index, piece) in pieces.enumerated() {
            try Task.checkCancellation()
            // A piece whose predicted audio overflows its bucket is split and rendered in halves
            // rather than losing the sentence to 200 ms of silence (spec §6; Task 3,
            // `spikes/findings/2026-09-05-coreml-audio-quality.md`), so one piece from `pieces` may
            // become several rendered pieces here.
            let rendered = try renderWithSplitting(
                piece, isFinal: index == pieces.count - 1, words: words, tokenizer: tokenizer, loaded: loaded
            )
            for (subPiece, result) in rendered {
                // With a crossfade the join overlaps the last 5 ms of the previous piece, so the
                // piece's audio starts that much earlier than a plain append would put it.
                let joined = options.crossfadePieces && !samples.isEmpty
                    ? PcmJoiner.join(segments: [samples, result.audio], sampleRate: PipelineConstants.sampleRate)
                    : samples + result.audio
                let offsetSamples = joined.count - result.audio.count
                folds.append(KokoroCoreMLTimingFold.Piece(
                    owners: subPiece.owners,
                    frames: result.tokenDurationFrames,
                    offsetSeconds: Double(offsetSamples) / Double(PipelineConstants.sampleRate)
                ))
                samples = joined
            }
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
                    speed: 1.0,
                    punctuationSuppression: options.punctuationSuppression
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

    /// Renders `piece` and, when the pipeline predicted more audio than the piece's bucket holds
    /// (``KokoroCoreMLError/audioTruncated``), splits it at the boundary nearest its middle — the
    /// same preference order ``pieces(ids:owners:words:)`` uses at the cap: a sentence ending, else
    /// a clause boundary, else any group boundary — and renders each half in turn, instead of
    /// losing the sentence to 200 ms of silence (spec §6;
    /// `spikes/findings/2026-09-05-coreml-audio-quality.md`). A half that overflows again is split
    /// again; the recursion is bounded by `piece`'s group count, since a piece that is already a
    /// single group still throws on overflow — there is nothing left to cut. `isFinal` is whether
    /// `piece` is the whole utterance's last piece, so a split second half can still inherit the
    /// token range that charges trailing zero-id tokens to the last piece (see
    /// ``pieces(ids:owners:words:)``).
    ///
    /// The cutting rule lives in ``renderSplittingOnOverflow(_:isFinal:words:render:)``, which this
    /// calls with a closure over ``render(_:tokenizer:loaded:)``. That closure only ever runs
    /// synchronously, on this call's own stack, and never outlives it — but Swift's actor-isolation
    /// checker cannot see that for a closure passed as an argument, and flags `loaded` (reused on
    /// every iteration of `synthesize`'s loop) as unsafe to capture repeatedly. Calling `render`
    /// directly here, rather than through the shared closure-based helper, keeps the production
    /// path a plain same-actor call with no closure at all.
    private func renderWithSplitting(
        _ piece: Piece, isFinal: Bool, words: [MToken], tokenizer: KokoroTokenizer, loaded: Loaded
    ) throws -> [(piece: Piece, result: KokoroPipelineResult)] {
        do {
            return [(piece, try render(piece, tokenizer: tokenizer, loaded: loaded))]
        } catch let error as KokoroCoreMLError {
            guard case .audioTruncated = error else { throw error }
            let groups = Self.groups(ids: piece.ids, owners: piece.owners)
            guard groups.count > 1 else { throw error }
            let cutIndex = Self.middleCutIndex(in: groups)
            let (first, second) = Self.splitPiece(groups: groups, at: cutIndex, isFinal: isFinal, words: words)
            return try renderWithSplitting(first, isFinal: false, words: words, tokenizer: tokenizer, loaded: loaded)
                + (try renderWithSplitting(second, isFinal: isFinal, words: words, tokenizer: tokenizer, loaded: loaded))
        }
    }

    /// The same recursion as ``renderWithSplitting(_:isFinal:words:tokenizer:loaded:)``, over an
    /// injected render call instead of the real pipeline. `static`, and so not actor-isolated: it
    /// touches no engine state — only `piece`'s own ids and owners, plus `words` for the halves'
    /// `phonemeUTF16Count` — so a test can call it directly, on any machine, with a fake `renderOne`
    /// that makes the first attempt throw ``KokoroCoreMLError/audioTruncated`` and asserts the
    /// halves that follow, without a real Core ML stage or any actor-isolation ceremony.
    static func renderSplittingOnOverflow(
        _ piece: Piece, isFinal: Bool, words: [MToken], render renderOne: RenderPiece
    ) throws -> [(piece: Piece, result: KokoroPipelineResult)] {
        do {
            return [(piece, try renderOne(piece))]
        } catch let error as KokoroCoreMLError {
            guard case .audioTruncated = error else { throw error }
            let groups = Self.groups(ids: piece.ids, owners: piece.owners)
            guard groups.count > 1 else { throw error }
            let cutIndex = Self.middleCutIndex(in: groups)
            let (first, second) = Self.splitPiece(groups: groups, at: cutIndex, isFinal: isFinal, words: words)
            return try renderSplittingOnOverflow(first, isFinal: false, words: words, render: renderOne)
                + (try renderSplittingOnOverflow(second, isFinal: isFinal, words: words, render: renderOne))
        }
    }

    /// Splits `piece` at `cutIndex` into its `groups` before and after: two new `Piece`s whose ids
    /// and owners tile `piece`'s exactly, each with its own `phonemeUTF16Count`. Each half counts
    /// from its own first group's token, so a token that phonemized to no id between the halves is
    /// charged to neither (``pieces(ids:owners:words:)`` charges it to the following piece) — a
    /// difference of a character or two in the voice-row lookup, on a path only an overflow reaches.
    /// `extendToEnd` on the second half preserves the charge to trailing zero-id tokens when `piece`
    /// was the whole utterance's last.
    private static func splitPiece(
        groups: [Group], at cutIndex: Int, isFinal: Bool, words: [MToken]
    ) -> (first: Piece, second: Piece) {
        let firstGroups = groups[0 ... cutIndex]
        let secondGroups = groups[(cutIndex + 1)...]
        let (first, _) = Self.piece(
            from: firstGroups, firstToken: firstGroups.first?.token ?? 0, words: words, extendToEnd: false
        )
        let (second, _) = Self.piece(
            from: secondGroups, firstToken: secondGroups.first?.token ?? 0, words: words, extendToEnd: isFinal
        )
        return (first, second)
    }

    /// How many pipeline ids `spoken` phonemizes to for `voice`, and the phonemized string itself —
    /// what the segmenter's utterance length has to be calibrated against. Internal, for the audio
    /// probe; it loads the G2P and the voice table but no Core ML stage.
    func phonemization(of spoken: String, voice: String) throws -> (ids: Int, phonemes: String) {
        guard let voiceURL = resources.voices[voice] else { throw KokoroCoreMLError.unknownVoice(voice) }
        let tokenizer = try tokenizer(voice: voice, url: voiceURL)
        let words = MLX.Device.withDefaultDevice(.cpu) {
            g2p(british: voice.hasPrefix("b")).phonemize(text: spoken).1
        }
        let (phonemes, owners) = Self.phonemeWalk(words)
        return (tokenizer.tokenize(phonemes: phonemes, ownersByCharacter: owners).ids.count, phonemes)
    }

    private func tokenizer(voice: String, url: URL) throws -> KokoroTokenizer {
        if let cached = tokenizers[voice] { return cached }
        let tokenizer = try KokoroTokenizer(vocabURL: resources.vocab, voiceURL: url)
        tokenizers[voice] = tokenizer
        return tokenizer
    }

    /// MisakiSwift's fallback network applies MLXNN's `gelu`, which is an MLX *compiled* function. On
    /// the CPU backend MLX builds its fused kernels at run time with a C compiler, and iOS has none, so
    /// the first out-of-lexicon word on a pre-A14 phone died with "[Compiled::eval_cpu] CPU compilation
    /// not supported on the platform" (iPhone 11 Pro, 2026-09-04; the spike corpus never had an unknown
    /// word, a book has one on every page). With compilation disabled every compiled function runs its
    /// plain graph instead. The switch is process-global: the MLX Kokoro engine wired beside this one
    /// loses its fused kernels too, which costs that benchmark-only route some speed on an A14+ phone
    /// and nothing else. Evaluated once, before the first G2P exists.
    private static let mlxCompilationDisabled: Void = MLX.compile(enable: false)

    /// The G2P for a language, built once and kept.
    ///
    /// MisakiSwift's out-of-lexicon fallback is a BART network on MLX, whose GEMMs are exactly what a
    /// pre-A14 GPU cannot run — so both the construction and every `phonemize` call are wrapped in
    /// `MLX.Device.withDefaultDevice(.cpu)`, which is a task-local. Deliberately *not*
    /// `MLX.Device.setDefault`: that is process-global, and the MLX Kokoro engine is wired beside this
    /// one in the app, where pinning the process to the CPU would cripple it (RTF 15).
    private func g2p(british: Bool) -> EnglishG2P {
        if let cached = british ? britishG2P : americanG2P { return cached }
        _ = Self.mlxCompilationDisabled
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

    /// One piece's render call, as ``renderSplittingOnOverflow(_:isFinal:words:render:)`` takes it —
    /// a plain closure, not `@Sendable`: that function is `static` (not actor-isolated), so nothing
    /// calling it, including a test, ever crosses into the actor at all.
    typealias RenderPiece = (Piece) throws -> KokoroPipelineResult

    /// One Misaki token's ids plus the whitespace that follows it: the smallest unit a piece
    /// boundary — at the cap, or at a later split of a piece that overflowed its bucket — may fall
    /// between.
    typealias Group = (token: Int, ids: [Int32], owners: [Int])

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

    /// Groups `ids` by the Misaki token that contributed them: one Misaki token's ids plus the
    /// whitespace ids that follow it make one group, so a piece boundary can only ever fall between
    /// two groups, never inside one.
    private static func groups(ids: [Int32], owners: [Int]) -> [Group] {
        var groups: [Group] = []
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
        return groups
    }

    /// Whether `group`'s last id — ignoring the trailing whitespace ids that follow the token it
    /// belongs to — is one of `tokenIds`. Trailing ids are found by owner (``KokoroCoreMLTimingFold/noOwner``),
    /// not by id value, so this reads correctly whatever the vocabulary assigns to whitespace.
    private static func groupEnds(_ group: Group, with tokenIds: Set<Int32>) -> Bool {
        for index in stride(from: group.ids.count - 1, through: 0, by: -1) where group.owners[index] != KokoroCoreMLTimingFold.noOwner {
            return tokenIds.contains(group.ids[index])
        }
        return false
    }

    /// Where to close the current piece when the next group would overflow the cap: the last group
    /// in `current` that ends a sentence, else the last that ends a clause, else all of `current` —
    /// the cutter's original rule, kept as the last resort. A long sentence cut at a bare word and
    /// butted to the next left an audible seam; cutting where the duration model already predicts a
    /// pause hides it (`spikes/findings/2026-09-05-coreml-audio-quality.md`). The groups after the
    /// returned index start the next piece.
    private static func bestCutIndex(in current: [Group]) -> Int {
        // A boundary is only worth taking when the piece it closes is at least half a call's worth of
        // ids: a comma twenty ids into a 250-id sentence would otherwise make a tiny first piece and
        // three calls where two would do — and every call ends with Kokoro's long predicted tail.
        var idsThrough = 0
        var minimumIndex = current.count
        for (index, group) in current.enumerated() {
            idsThrough += group.ids.count
            if idsThrough * 2 >= maxPieceTokenCount { minimumIndex = index; break }
        }
        func lastBoundary(_ tokenIds: Set<Int32>) -> Int? {
            current.lastIndex(where: { Self.groupEnds($0, with: tokenIds) }).flatMap { $0 >= minimumIndex ? $0 : nil }
        }
        if let index = lastBoundary(KokoroVocabulary.sentenceFinalPunctuationTokenIds) { return index }
        if let index = lastBoundary(KokoroVocabulary.clauseBoundaryPunctuationTokenIds) { return index }
        return current.count - 1
    }

    /// Where to split a piece whose predicted audio overflowed its bucket: the boundary closest to
    /// the middle by id count, in the same preference order as ``bestCutIndex(in:)`` — a sentence
    /// ending, else a clause boundary, else any group boundary. Never the last index, so the second
    /// half is never empty; `groups.count > 1` is the caller's responsibility.
    private static func middleCutIndex(in groups: [Group]) -> Int {
        let target = groups.reduce(0) { $0 + $1.ids.count } / 2
        var idsThroughIndex: [Int] = []
        var running = 0
        for group in groups {
            running += group.ids.count
            idsThroughIndex.append(running)
        }
        let eligible = Array(groups.indices.dropLast())
        func closestToMiddle(among candidates: [Int]) -> Int? {
            candidates.min { abs(idsThroughIndex[$0] - target) < abs(idsThroughIndex[$1] - target) }
        }
        if let index = closestToMiddle(among: eligible.filter { Self.groupEnds(groups[$0], with: KokoroVocabulary.sentenceFinalPunctuationTokenIds) }) {
            return index
        }
        if let index = closestToMiddle(among: eligible.filter { Self.groupEnds(groups[$0], with: KokoroVocabulary.clauseBoundaryPunctuationTokenIds) }) {
            return index
        }
        return closestToMiddle(among: eligible) ?? 0
    }

    /// Builds one `Piece` from a contiguous run of groups: every id and owner concatenated in
    /// order, and the UTF-16 length of the Misaki tokens it spans, read from `words` between
    /// `firstToken` and either the last group's token or — for the piece that reaches the end of
    /// the whole utterance — `words.count - 1`, so any trailing tokens that contributed no id at
    /// all are still charged to that last piece. Returns the token index the next piece should
    /// start counting from.
    private static func piece(
        from groups: ArraySlice<Group>, firstToken: Int, words: [MToken], extendToEnd: Bool
    ) -> (piece: Piece, lastToken: Int) {
        var piece = Piece()
        for group in groups {
            piece.ids += group.ids
            piece.owners += group.owners
        }
        let lastToken = extendToEnd ? max(firstToken, words.count - 1) : (groups.last?.token ?? firstToken)
        piece.phonemeUTF16Count = (firstToken ... lastToken).reduce(0) {
            $0 + ((words[$1].phonemes ?? unknownPhoneme) + words[$1].whitespace).utf16.count
        }
        return (piece, lastToken)
    }

    /// Cuts the utterance's ids into consecutive pieces of at most ``maxPieceTokenCount`` ids,
    /// greedily and only between Misaki tokens: a group whose ids would push the current piece over
    /// the cap starts the next one, unless a sentence or clause boundary earlier in the current
    /// piece gives it a better place to close (``bestCutIndex(in:)``) — the groups after that
    /// boundary carry over into the piece that starts with the overflowing group, which is checked
    /// against the cap again in turn, so a boundary near the start of a very long run cannot itself
    /// produce an oversized piece.
    ///
    /// Internal rather than private so the cut can be tested on synthetic ids, on a machine with no
    /// model files: end to end this rule is only visible in an utterance long enough to need two
    /// pipeline calls, which is a minute of Core ML per run.
    static func pieces(ids: [Int32], owners: [Int], words: [MToken]) throws -> [Piece] {
        let groups = Self.groups(ids: ids, owners: owners)

        var packed: [[Group]] = []
        var current: [Group] = []
        var currentCount = 0
        for group in groups {
            guard group.ids.count <= maxPieceTokenCount else {
                // One word longer than a whole pipeline input. Nothing to split it at.
                throw KokoroCoreMLError.tooManyTokens(group.ids.count)
            }
            while currentCount + group.ids.count > maxPieceTokenCount, !current.isEmpty {
                let cutIndex = Self.bestCutIndex(in: current)
                packed.append(Array(current[0 ... cutIndex]))
                current = Array(current[(cutIndex + 1)...])
                currentCount = current.reduce(0) { $0 + $1.ids.count }
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
        for (index, groupSlice) in packed.enumerated() {
            let (piece, lastToken) = Self.piece(
                from: groupSlice[...], firstToken: firstToken, words: words, extendToEnd: index == packed.count - 1
            )
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
