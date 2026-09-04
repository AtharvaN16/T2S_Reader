import Foundation
import MLXUtilsLibrary
import Testing
import T2SAudio
import T2SCore
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
    /// test compiles and loads for itself and nothing carries state between them.
    static func engineWithRealResources() throws -> KokoroCoreMLEngine {
        KokoroTestSupport.locatePackageResourceBundles()
        return KokoroCoreMLEngine(
            resources: try KokoroCoreMLResources.locate(inDirectory: KokoroCoreMLResources.developmentDirectory).get()
        )
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

    // MARK: The real model

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func synthesizesAnAmericanSentenceWithWordTimings() async throws {
        let engine = try Self.engineWithRealResources()
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
        let engine = try Self.engineWithRealResources()
        let result = try await engine.synthesize(.init(
            spoken: "The quick brown fox jumps over the lazy dog.",
            voiceID: Self.voiceID("bf_emma")
        ))
        #expect(result.audio.duration > 0.5)
        #expect(Self.rms(result.audio.samples) > 0.01)
    }

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func rejectsAnUnknownVoice() async throws {
        let engine = try Self.engineWithRealResources()
        await #expect(throws: KokoroCoreMLError.unknownVoice("zz_nobody")) {
            try await engine.synthesize(.init(spoken: "Hello.", voiceID: Self.voiceID("zz_nobody")))
        }
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
        let engine = try Self.engineWithRealResources()
        let result = try await engine.synthesize(.init(spoken: Self.longSentence, voiceID: Self.voiceID("af_heart")))

        #expect(result.audio.duration > 15)
        #expect(result.wordTimings.count == Self.longSentence.split(separator: " ").count)
        #expect(result.wordTimings.map(\.start) == result.wordTimings.map(\.start).sorted())
        #expect(result.wordTimings.last!.end <= result.audio.duration + 0.001)
        let biggestBackwardsStep = zip(result.wordTimings.dropFirst(), result.wordTimings)
            .map { $1.end - $0.start }.max() ?? 0
        #expect(biggestBackwardsStep <= 0.5)

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
