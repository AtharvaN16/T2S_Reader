import Foundation
// `MToken` — the G2P's output type, which the chunker tests build by hand — is declared here.
import MLXUtilsLibrary
import Testing
import T2SAudio
import T2SCore
// For `SynthesisResult`/`StageTimings`, to build a fake render result in the splitting tests below
// without a real Core ML stage — neither type declares a public initializer.
@testable import KokoroPipeline
@testable import T2SKokoro

/// Serialized: the model-backed tests each compile and load eight Core ML stages, and running them
/// beside each other would measure contention rather than the engine.
@Suite(.serialized) struct KokoroCoreMLEngineTests {
    /// An engine over a staging that holds nothing. Every check `synthesize` makes before it loads a
    /// model can be tested through it, on any machine, in microseconds.
    static func engineWithoutResources() -> KokoroCoreMLEngine {
        KokoroCoreMLEngine(resources: KokoroCoreMLResources.Located(
            stages: [:], voices: [:],
            vocab: URL(filePath: "/nonexistent/T2SKokoroTests/kokoro-vocab.json"),
            hnsfWeights: URL(filePath: "/nonexistent/T2SKokoroTests/hnsf_weights.json"),
            isPrecompiled: false
        ))
    }

    /// A fresh engine over the staged model files. Per test rather than shared, so each model-backed
    /// test loads its own stages and nothing carries state between them — but every engine shares
    /// one compile of the staging (``KokoroTestSupport/compiledCoreMLResources()``), so running the
    /// whole suite does not write a fresh ~350 MB copy into `$TMPDIR` per test.
    static func engineWithRealResources() async throws -> KokoroCoreMLEngine {
        KokoroTestSupport.locatePackageResourceBundles()
        return KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources())
    }

    static func voiceID(_ voice: String) -> String {
        KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: voice).rawValue
    }

    // MARK: Identity

    @Test func identityIsPinnedToTheRevisionAndRuntime() {
        #expect(KokoroCoreMLEngine.identity == "kokoro-coreml-2e878c6a-misaki1.0.6")
        #expect(KokoroCoreMLEngine.runtime == "coreml-cpu")
        #expect(Self.engineWithoutResources().engineID == KokoroCoreMLEngine.identity)
    }

    // MARK: Checks that happen before anything is loaded

    @Test(arguments: [
        "kokoro:other:af_heart",    // Kokoro, but not this staging
        "system:x",                 // the system route
        "af_heart",                 // a bare voice name
    ])
    func refusesAnotherEngineIdentityBeforeLoading(voiceID: String) async {
        let engine = Self.engineWithoutResources()
        await #expect(throws: KokoroCoreMLError.voiceNotForThisEngine(voiceID)) {
            try await engine.synthesize(.init(spoken: "Hello", voiceID: voiceID))
        }
    }

    @Test func refusesTextWithNothingToSpeak() async {
        let engine = Self.engineWithoutResources()
        await #expect(throws: SynthesisError.failed("nothing to speak")) {
            try await engine.synthesize(.init(spoken: "   ", voiceID: Self.voiceID("af_heart")))
        }
    }

    /// A render cancelled before it reaches the front of the engine's queue must not compile eight
    /// Core ML stages and synthesize for seconds: the scheduler cancels pending work on stop, and
    /// this actor's queue is serial, so the next real render would wait behind it.
    @Test func aCancelledRenderLeavesTheQueueWithoutLoadingAnything() async {
        let engine = Self.engineWithoutResources()
        let render = Task {
            // Deterministic: the render is only attempted once this task is already cancelled.
            while !Task.isCancelled { await Task.yield() }
            return try await engine.synthesize(.init(spoken: "Hello.", voiceID: Self.voiceID("af_heart")))
        }
        render.cancel()
        await #expect(throws: CancellationError.self) { _ = try await render.value }
    }

    // MARK: Chunking, on synthetic ids

    /// A Misaki token as the chunker sees it: the phonemes it contributed and the whitespace that
    /// follows. `tokenRange` is required by `MToken` and is never read here.
    static func word(_ text: String, phonemes: String, whitespace: String = " ") -> MToken {
        MToken(text: text, tokenRange: text.startIndex ..< text.endIndex,
               whitespace: whitespace, phonemes: phonemes)
    }

    /// The ordinary case, which is every sentence the app's segmenter produces: one pipeline call
    /// carrying every id, and the whole phonemized string's length for `refS` — the same number the
    /// §7.3 spike measured with.
    @Test func keepsAShortUtteranceInOnePiece() throws {
        let words = [Self.word("Hi", phonemes: "hˈI"), Self.word("there", phonemes: "ðˈɛɹ", whitespace: "")]
        let pieces = try KokoroCoreMLEngine.pieces(
            ids: [1, 2, 3, 0, 4, 5],
            owners: [0, 0, 0, KokoroCoreMLTimingFold.noOwner, 1, 1],
            words: words
        )
        #expect(pieces.count == 1)
        #expect(pieces[0].ids == [1, 2, 3, 0, 4, 5])
        #expect(pieces[0].owners == [0, 0, 0, KokoroCoreMLTimingFold.noOwner, 1, 1])
        #expect(pieces[0].phonemeUTF16Count == "hˈI ðˈɛɹ".utf16.count)
    }

    /// Past the cap the ids are cut, and only between words: no id is lost, reordered or duplicated,
    /// no piece is over the cap, and the whitespace after a word never leads the next piece — its
    /// frames are the pause after that word, and the pause has to be synthesized beside it.
    @Test func cutsALongUtteranceAtTokenBoundaries() throws {
        // Sixty words of four phonemes and a space: 300 ids, well past the 176-id cap.
        let words = (0 ..< 60).map { Self.word("w\($0)", phonemes: "abcd") }
        var ids: [Int32] = []
        var owners: [Int] = []
        for index in 0 ..< 60 {
            ids += [1, 2, 3, 4, 0]
            owners += Array(repeating: index, count: 4) + [KokoroCoreMLTimingFold.noOwner]
        }

        let pieces = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)

        #expect(pieces.count == 2)
        #expect(pieces.flatMap(\.ids) == ids)
        #expect(pieces.flatMap(\.owners) == owners)
        let everyPieceFits = pieces.allSatisfy { $0.ids.count <= KokoroCoreMLEngine.maxPieceTokenCount }
        #expect(everyPieceFits)
        let noPieceLeadsWithAPause = pieces.allSatisfy { $0.owners.first != KokoroCoreMLTimingFold.noOwner }
        #expect(noPieceLeadsWithAPause)
        // The pieces tile the token list, so their `refS` lengths add up to the whole string's.
        #expect(pieces.map(\.phonemeUTF16Count).reduce(0, +) == 60 * "abcd ".utf16.count)
    }

    /// One word that phonemizes to more ids than a whole pipeline input holds. There is no boundary
    /// left to cut at, so the utterance fails and spec §6 fills it with 200 ms of silence — far
    /// better than the clipped speech the bucket would otherwise return.
    @Test func refusesASingleWordLongerThanOnePipelineInput() {
        let count = KokoroCoreMLEngine.maxPieceTokenCount + 1
        let words = [Self.word("unpronounceable", phonemes: String(repeating: "a", count: count), whitespace: "")]
        #expect(throws: KokoroCoreMLError.tooManyTokens(count)) {
            try KokoroCoreMLEngine.pieces(ids: Array(repeating: 1, count: count),
                                          owners: Array(repeating: 0, count: count),
                                          words: words)
        }
    }

    /// Builds `count` synthetic four-phoneme words (ids `phonemeIds` plus a trailing whitespace id
    /// of `KokoroCoreMLTimingFold.noOwner`) starting at word index `startIndex`, appending to
    /// `words`/`ids`/`owners` in place. `phonemeIds` deliberately avoids every id in
    /// `KokoroVocabulary.silentPunctuationTokenIds` (1–15), so these words never accidentally read
    /// as a sentence or clause boundary.
    static func appendPlainWords(
        count: Int, startIndex: Int, phonemeIds: [Int32] = [20, 21, 22, 23],
        words: inout [MToken], ids: inout [Int32], owners: inout [Int]
    ) {
        for index in startIndex ..< startIndex + count {
            words.append(Self.word("w\(index)", phonemes: "abcd"))
            ids += phonemeIds + [16]
            owners += Array(repeating: index, count: phonemeIds.count) + [KokoroCoreMLTimingFold.noOwner]
        }
    }

    /// A full stop deep inside the window before the cap: the cutter must close the piece right
    /// after it rather than at the last word, because a real pause is already predicted there
    /// (`spikes/findings/2026-09-05-coreml-audio-quality.md`).
    @Test func cutsAfterAFullStopWhenOneExistsInsideTheWindow() throws {
        var words: [MToken] = []
        var ids: [Int32] = []
        var owners: [Int] = []
        Self.appendPlainWords(count: 20, startIndex: 0, words: &words, ids: &ids, owners: &owners)
        // The full stop: its own Misaki token (owner 20), one id, then its own trailing whitespace.
        words.append(Self.word(".", phonemes: "."))
        ids += [4, 16]
        owners += [20, KokoroCoreMLTimingFold.noOwner]
        Self.appendPlainWords(count: 20, startIndex: 21, words: &words, ids: &ids, owners: &owners)

        let pieces = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)

        #expect(pieces.count > 1)
        #expect(pieces.flatMap(\.ids) == ids)
        #expect(pieces.flatMap(\.owners) == owners)
        // The first piece ends exactly at the full stop's group: its id and trailing whitespace.
        #expect(pieces[0].ids.suffix(2) == [4, 16])
        let everyPieceFits = pieces.allSatisfy { $0.ids.count <= KokoroCoreMLEngine.maxPieceTokenCount }
        #expect(everyPieceFits)
    }

    /// No full stop anywhere, but a comma deep inside the window: the cutter falls back to the
    /// clause boundary rather than the last word.
    @Test func cutsAfterACommaWhenOnlyAClauseBoundaryExists() throws {
        var words: [MToken] = []
        var ids: [Int32] = []
        var owners: [Int] = []
        Self.appendPlainWords(count: 20, startIndex: 0, words: &words, ids: &ids, owners: &owners)
        // The comma: its own Misaki token (owner 20), one id, then its own trailing whitespace.
        words.append(Self.word(",", phonemes: ","))
        ids += [3, 16]
        owners += [20, KokoroCoreMLTimingFold.noOwner]
        Self.appendPlainWords(count: 20, startIndex: 21, words: &words, ids: &ids, owners: &owners)

        let pieces = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)

        #expect(pieces.count > 1)
        #expect(pieces.flatMap(\.ids) == ids)
        #expect(pieces.flatMap(\.owners) == owners)
        #expect(pieces[0].ids.suffix(2) == [3, 16])
        let everyPieceFits = pieces.allSatisfy { $0.ids.count <= KokoroCoreMLEngine.maxPieceTokenCount }
        #expect(everyPieceFits)
    }

    /// A comma too early in the window is not worth a cut: closing the piece there would make a tiny
    /// first call and three calls where two would do, each ending in Kokoro's long predicted tail.
    /// The cutter takes a boundary only when the piece it closes holds at least half the cap.
    @Test func ignoresAClauseBoundaryThatWouldLeaveATinyPiece() throws {
        var words: [MToken] = []
        var ids: [Int32] = []
        var owners: [Int] = []
        Self.appendPlainWords(count: 3, startIndex: 0, words: &words, ids: &ids, owners: &owners)
        words.append(Self.word(",", phonemes: ","))
        ids += [3, 16]
        owners += [3, KokoroCoreMLTimingFold.noOwner]
        Self.appendPlainWords(count: 40, startIndex: 4, words: &words, ids: &ids, owners: &owners)

        let pieces = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)

        #expect(pieces.count == 2)
        #expect(pieces.flatMap(\.ids) == ids)
        #expect(pieces[0].ids.suffix(2) != [3, 16])
        #expect(pieces[0].ids.count > KokoroCoreMLEngine.maxPieceTokenCount / 2)
    }

    /// No punctuation anywhere in the run: the cutter falls back to the last word, same as before
    /// either kind of boundary existed. Ids are chosen so none of them coincide with a real
    /// vocabulary punctuation id, unlike ``cutsALongUtteranceAtTokenBoundaries``'s ids 1–4.
    @Test func cutsAtTheLastWordWhenNoPunctuationBoundaryExists() throws {
        var words: [MToken] = []
        var ids: [Int32] = []
        var owners: [Int] = []
        Self.appendPlainWords(count: 60, startIndex: 0, words: &words, ids: &ids, owners: &owners)

        let pieces = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)

        #expect(pieces.count == 2)
        #expect(pieces.flatMap(\.ids) == ids)
        #expect(pieces.flatMap(\.owners) == owners)
        let everyPieceFits = pieces.allSatisfy { $0.ids.count <= KokoroCoreMLEngine.maxPieceTokenCount }
        #expect(everyPieceFits)
        let noPieceLeadsWithAPause = pieces.allSatisfy { $0.owners.first != KokoroCoreMLTimingFold.noOwner }
        #expect(noPieceLeadsWithAPause)
    }

    /// The piece after a cut carries the kind of cut, which is what Task 3's seam budget keys on.
    @Test func recordsTheKindOfCutBeforeEachPiece() throws {
        var words: [MToken] = []
        var ids: [Int32] = []
        var owners: [Int] = []
        Self.appendPlainWords(count: 60, startIndex: 0, words: &words, ids: &ids, owners: &owners)
        let wordCut = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)
        #expect(wordCut.map(\.cut) == [.none, .word])

        words = []; ids = []; owners = []
        Self.appendPlainWords(count: 20, startIndex: 0, words: &words, ids: &ids, owners: &owners)
        words.append(Self.word(",", phonemes: ","))
        ids += [3, 16]
        owners += [20, KokoroCoreMLTimingFold.noOwner]
        Self.appendPlainWords(count: 20, startIndex: 21, words: &words, ids: &ids, owners: &owners)
        let commaCut = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)
        #expect(commaCut.map(\.cut) == [.none, .clause])

        words = []; ids = []; owners = []
        Self.appendPlainWords(count: 20, startIndex: 0, words: &words, ids: &ids, owners: &owners)
        words.append(Self.word(".", phonemes: "."))
        ids += [4, 16]
        owners += [20, KokoroCoreMLTimingFold.noOwner]
        Self.appendPlainWords(count: 20, startIndex: 21, words: &words, ids: &ids, owners: &owners)
        let stopCut = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)
        #expect(stopCut.map(\.cut) == [.none, .sentence])
    }

    // MARK: Splitting a piece that overflowed its bucket

    /// A minimal, plausible pipeline result: only what the splitting logic and its tests read
    /// (`audio`, `tokenDurationFrames`) need to be meaningful, everything else is a placeholder.
    /// Neither `KokoroPipelineResult` (T2SKokoro's name for `KokoroPipeline.SynthesisResult` — the
    /// module and one of its own classes share that name) nor `StageTimings` declares a public
    /// initializer, which is why this file imports `KokoroPipeline` with `@testable`.
    static func fakeRenderResult(audio: [Float] = [0.1], frames: [Int] = [1]) -> KokoroPipelineResult {
        KokoroPipelineResult(
            audio: audio, timings: StageTimings(), bucketSeconds: 15,
            audioDurationSeconds: Double(audio.count) / 24_000, wallTimeSeconds: 0,
            predictedDurationFrames: frames.reduce(0, +), predictedDurationTokens: frames.count,
            durationModelCacheKey: "test", durationModelAllowsPadding: true, durationTokenLength: 128,
            tFrames: 1, fullF0Length: 1, decoderFrameCount: 1, xPreExpectedTime: 1, harExpectedTime: 1,
            trimSampleCount: audio.count, tokenDurationFrames: frames
        )
    }

    /// A piece whose whole render overflows its bucket splits into its two groups and both render
    /// successfully — no model, no `synthesize`, no engine instance at all:
    /// ``KokoroCoreMLEngine/renderSplittingOnOverflow(_:isFinal:words:render:)`` is `static`, and
    /// the fake `render` closure stands in for ``KokoroCoreMLEngine/render(_:tokenizer:loaded:)``.
    @Test func splitsAPieceThatOverflowsItsBucketInsteadOfDroppingItToSilence() throws {
        let words = [Self.word("one", phonemes: "on"), Self.word("two", phonemes: "tu", whitespace: "")]
        let piece = try KokoroCoreMLEngine.pieces(
            ids: [1, 2, 0, 3, 4],
            owners: [0, 0, KokoroCoreMLTimingFold.noOwner, 1, 1],
            words: words
        )[0]

        var attempts: [[Int32]] = []
        let outcome = try KokoroCoreMLEngine.renderSplittingOnOverflow(piece, isFinal: true, words: words) { attempted in
            attempts.append(attempted.ids)
            if attempted.ids == [1, 2, 0, 3, 4] {
                throw KokoroCoreMLError.audioTruncated(predictedSeconds: 20, bucketSeconds: 15)
            }
            return Self.fakeRenderResult()
        }

        #expect(attempts == [[1, 2, 0, 3, 4], [1, 2, 0], [3, 4]])
        #expect(outcome.map { $0.piece.ids } == [[1, 2, 0], [3, 4]])
        #expect(outcome.flatMap { $0.piece.ids } == piece.ids)
        #expect(outcome.flatMap { $0.piece.owners } == piece.owners)
    }

    /// A half that itself overflows is split again — bounded by the group count, since a single
    /// group that overflows still throws (the next test).
    @Test func aHalfThatStillOverflowsIsSplitAgain() throws {
        // Four one-id words, each with a trailing whitespace id except the last.
        let words = (0 ..< 4).map { Self.word("w\($0)", phonemes: "a", whitespace: $0 == 3 ? "" : " ") }
        let ids: [Int32] = [10, 0, 11, 0, 12, 0, 13]
        let owners = [0, KokoroCoreMLTimingFold.noOwner, 1, KokoroCoreMLTimingFold.noOwner,
                      2, KokoroCoreMLTimingFold.noOwner, 3]
        let piece = try KokoroCoreMLEngine.pieces(ids: ids, owners: owners, words: words)[0]

        var attempts: [[Int32]] = []
        let outcome = try KokoroCoreMLEngine.renderSplittingOnOverflow(piece, isFinal: true, words: words) { attempted in
            attempts.append(attempted.ids)
            // Overflow the whole piece and its second half (three groups); everything else fits.
            if attempted.ids == ids || attempted.ids == [11, 0, 12, 0, 13] {
                throw KokoroCoreMLError.audioTruncated(predictedSeconds: 20, bucketSeconds: 15)
            }
            return Self.fakeRenderResult()
        }

        #expect(attempts.count == 5)
        #expect(outcome.map { $0.piece.ids } == [[10, 0], [11, 0], [12, 0, 13]])
        #expect(outcome.flatMap { $0.piece.ids } == piece.ids)
    }

    /// A piece that is already a single group cannot be split any further: an overflow there still
    /// throws, exactly as it does today for the whole utterance.
    @Test func aSingleGroupThatOverflowsStillThrows() throws {
        let words = [Self.word("a", phonemes: "a", whitespace: "")]
        let piece = try KokoroCoreMLEngine.pieces(ids: [10], owners: [0], words: words)[0]

        #expect(throws: KokoroCoreMLError.audioTruncated(predictedSeconds: 20, bucketSeconds: 15)) {
            _ = try KokoroCoreMLEngine.renderSplittingOnOverflow(piece, isFinal: true, words: words) { _ in
                throw KokoroCoreMLError.audioTruncated(predictedSeconds: 20, bucketSeconds: 15)
            }
        }
    }

    // MARK: The real model

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func synthesizesAnAmericanSentenceWithWordTimings() async throws {
        let engine = try await Self.engineWithRealResources()
        let loadStarted = Date()
        try await engine.preload()
        let loadSeconds = Date().timeIntervalSince(loadStarted)

        let synthesisStarted = Date()
        let result = try await engine.synthesize(.init(
            spoken: "The quick brown fox jumps over the lazy dog.",
            voiceID: Self.voiceID("af_heart")
        ))
        let synthesisSeconds = Date().timeIntervalSince(synthesisStarted)

        #expect(result.audio.sampleRate == 24_000)
        #expect((1.0 ... 6.0).contains(result.audio.duration))
        // Hoisted: `#expect` decomposes the expression and cannot see through `allSatisfy`'s `rethrows`.
        let everySampleIsFinite = result.audio.samples.allSatisfy(\.isFinite)
        #expect(everySampleIsFinite)
        #expect(Self.rms(result.audio.samples) > 0.01)

        // Nine words, and no timing for the period: the full stop owns the breath after the sentence
        // but is not a word to highlight.
        #expect(result.wordTimings.count == 9)
        #expect(result.wordTimings.map(\.start) == result.wordTimings.map(\.start).sorted())
        #expect(result.wordTimings.last!.end <= result.audio.duration + 0.001)
        #expect(result.wordTimings.first!.spokenRange == 0 ..< 3)   // "The"

        // The plan takes its real-time factor from the A13; this line records the Mac's, which is the
        // only number this task can measure. Hidden by `scripts/test-kokoro.sh`'s output filter.
        print(String(format: "kokoro-coreml measurement: load %.2fs, synthesis %.2fs for %.2fs of audio (RTF %.3f)",
                     loadSeconds, synthesisSeconds, result.audio.duration,
                     synthesisSeconds / result.audio.duration))
    }

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func britishVoicesUseTheBritishG2P() async throws {
        let engine = try await Self.engineWithRealResources()
        let result = try await engine.synthesize(.init(
            spoken: "The quick brown fox jumps over the lazy dog.",
            voiceID: Self.voiceID("bf_emma")
        ))
        #expect(result.audio.duration > 0.5)
        #expect(Self.rms(result.audio.samples) > 0.01)
    }

    /// Words the lexicon does not know go through MisakiSwift's fallback network, which runs on MLX
    /// with compiled `gelu` activations. On iOS the CPU backend cannot compile at run time, and that
    /// killed the app on the iPhone 11 Pro on the first name in a book; the engine now disables MLX
    /// compilation before the fallback exists. This test walks that path, which no sentence in the
    /// other tests did.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func speaksWordsTheLexiconDoesNotKnow() async throws {
        let engine = try await Self.engineWithRealResources()
        let result = try await engine.synthesize(.init(
            spoken: "Vashtiquor greeted Zembrallion at the quay.",
            voiceID: Self.voiceID("af_heart")
        ))
        #expect(result.audio.duration > 1.0)
        #expect(Self.rms(result.audio.samples) > 0.01)
        #expect(result.wordTimings.count == 6)
    }

    /// A slow voice can predict more speech than the 15 s bucket holds for one packed utterance —
    /// `af_nicole` predicted 16.7 s for the first piece of the passage's 197-id utterance — and the
    /// vendored pipeline used to assert (DEBUG builds) before the engine's overflow re-split could run,
    /// taking a debug build, which is what the Phone scheme ships, down with it. Now the piece splits
    /// and the utterance renders whole.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func aSlowVoiceOnAPackedUtteranceRendersInsteadOfAsserting() async throws {
        let engine = try await Self.engineWithRealResources()
        let block = SourceBlock(text: KokoroAudioProbe.passage, position: Position(resourceHref: "probe", progression: 0, charOffset: 0))
        let utterance = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength).segment(block).map(\.spoken)[1]
        let result = try await engine.synthesize(.init(spoken: utterance, voiceID: Self.voiceID("af_nicole")))
        #expect(result.audio.duration > 15)
        #expect(Self.rms(result.audio.samples) > 0.01)
    }

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func rejectsAnUnknownVoice() async throws {
        let engine = try await Self.engineWithRealResources()
        await #expect(throws: KokoroCoreMLError.unknownVoice("zz_nobody")) {
            try await engine.synthesize(.init(spoken: "Hello.", voiceID: Self.voiceID("zz_nobody")))
        }
    }

    /// Loading suspends while the eight `.mlpackage` stages compile, and the actor is released
    /// across that suspension — so the wiring the app is headed for, `preload()` off the playback
    /// path and a render on play, arrives at a half-loaded engine twice. Both have to wait on the
    /// one compile: loading twice would build eight more compute plans (206 s on an A13's first
    /// launch after install) and hold two copies of the 119 MB until the first was dropped.
    ///
    /// `loadCount` is the only way to see the difference from outside — both spellings return the
    /// same audio, one of them several minutes later.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func loadsTheStagesOnceWhenAPreloadAndARenderArriveTogether() async throws {
        let engine = try await Self.engineWithRealResources()

        async let preloaded: Void = engine.preload()
        async let rendered = engine.synthesize(.init(spoken: "Hello there.", voiceID: Self.voiceID("af_heart")))
        try await preloaded
        let result = try await rendered

        let loadCount = await engine.loadCount
        #expect(loadCount == 1)
        #expect(result.audio.duration > 0.3)
        #expect(Self.rms(result.audio.samples) > 0.01)
    }

    /// The launch warm-up loads the stages so the first utterance does not wait for them; the G2P's
    /// two 3 MB lexicons and its fallback network are built the same way, or the first sentence a
    /// reader hears pays for them after the tap
    /// (`docs/superpowers/specs/2026-09-08-performance-audit.md` §3.2).
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func preloadBuildsTheG2P() async throws {
        let engine = try await Self.engineWithRealResources()
        #expect(await engine.isG2PLoaded == false)
        try await engine.preload()
        #expect(await engine.isG2PLoaded)
    }

    /// The app's segmenter allows 300 characters of source, which is more speech than the pipeline's
    /// largest bucket holds — so the engine splits the utterance at Misaki-token boundaries and
    /// concatenates the pieces. The seam has to be invisible in the timings: one timing per word, in
    /// order, inside the audio, with no hole where the pieces join.
    ///
    /// More than 15 seconds of audio is itself the proof that the cut happened: a single piece that
    /// predicted past its largest bucket would have thrown ``KokoroCoreMLError/audioTruncated``
    /// rather than come back clipped.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func synthesizesALongPassageInPieces() async throws {
        let engine = try await Self.engineWithRealResources()
        let result = try await engine.synthesize(.init(spoken: Self.longSentence, voiceID: Self.voiceID("af_heart")))

        #expect(result.audio.duration > 15)
        #expect(result.wordTimings.count == Self.longSentence.split(separator: " ").count)
        #expect(result.wordTimings.map(\.start) == result.wordTimings.map(\.start).sorted())
        #expect(result.wordTimings.last!.end <= result.audio.duration + 0.001)
        let biggestBackwardsStep = zip(result.wordTimings.dropFirst(), result.wordTimings)
            .map { $1.end - $0.start }.max() ?? 0
        #expect(biggestBackwardsStep <= 0.5)

        // Seams hold a beat, not a hole: no quiet stretch in the audio longer than the model's own
        // sentence pause. Before Plan 11 Task 3 the two seams measured 740 and 820 ms.
        let window = 240
        var longestQuietMs = 0
        var run = 0
        var i = 0
        while i + window <= result.audio.samples.count {
            let rms = (result.audio.samples[i ..< i + window].reduce(0) { $0 + $1 * $1 } / Float(window)).squareRoot()
            if rms < 0.00316 { run += 1 } else { longestQuietMs = max(longestQuietMs, run * 10); run = 0 }
            i += window
        }
        #expect(longestQuietMs <= 600)

        print(String(format: "kokoro-coreml long passage: %.2fs of audio, %d word timings",
                     result.audio.duration, result.wordTimings.count))
    }

    /// About seventy words, no numbers and no contractions, so every whitespace-separated chunk is
    /// one Misaki word token and the timing count can be asserted against a plain split.
    static let longSentence = """
        The old librarian walked slowly between the tall wooden shelves, humming a quiet tune to \
        herself while she gathered the books that the students had left scattered across the reading \
        tables, and she thought about the long winter evenings ahead, when the rain would drum \
        against the windows and the lamps would glow warmly over every open page, and nobody in the \
        whole building would say a single word for hours.
        """

    private static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(samples.count)).squareRoot()
    }
}
