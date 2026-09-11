import Dispatch
import Foundation
import KokoroPipeline
import MisakiSwift
import MLX
import os
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

    /// How many ids the first piece of a *streamed* utterance may carry: about three seconds of
    /// speech, which the 7 s bucket renders in about a second on an A13 — the first sound (Plan 14).
    /// The pieces after it are cut at ``maxPieceTokenCount`` as usual.
    static let streamingFirstPieceTokenCount = 48

    /// The most ids a piece rendered through the background set (``Options/backgroundComputeUnits``)
    /// may carry: ``streamingFirstPieceTokenCount`` (48 ids ≈ 3 s for a streamed head) with margin
    /// held back for slow speech, so the piece does not overflow the 3 s bucket
    /// (``KokoroCoreMLResources/backgroundBuckets`` = `[3]`) it renders in. Without this, a piece cut
    /// for the main set's 15 s bucket is rendered whole against the 3 s bucket first, overflows,
    /// and is halved and rendered again — a full pipeline run thrown away for nothing — before the
    /// audio comes back right (the review of 2026-09-11, §2.3(b), §3 R2).
    static let backgroundPieceTokenCount = 36

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
        /// Whether the click the pipeline leaves at the tail of every call is zeroed
        /// (``KokoroCoreMLTailClick``). The app ships `true`: the owner's second listen heard it as "a
        /// tick before the sentence resumes" wherever a call ends inside a sentence
        /// (`spikes/findings/2026-09-08-ticks-and-hyphens.md`).
        public var removeTailClick: Bool
        /// Whether the silence across a seam is trimmed to ``KokoroCoreMLSeam``'s budget for the cut
        /// that made it. The app ships `true`: with the tail click gone, a seam measured 400–820 ms
        /// against the 25–420 ms the model puts at the same boundary inside one call.
        public var trimSeams: Bool
        /// An experiment (`spikes/findings/2026-09-08-quality-levers.md`): how much the predicted
        /// pitch contour's movement is widened before the decoder, 1 being the model's own. The app
        /// ships 1 until the owner's ears say otherwise.
        public var f0Spread: Float
        /// Which compute units the stages load for. `.cpu` is the measured policy and what the app
        /// ships; the rest are a developer's switch for one session (``KokoroComputeUnits``).
        public var computeUnits: KokoroComputeUnits
        /// The compute units of a second, smaller set — ``KokoroCoreMLResources/backgroundBuckets``
        /// and ``KokoroCoreMLResources/backgroundDurationTokenLengths`` — that renders whatever the
        /// app's placement (``KokoroCoreMLEngine/setRenderPlacement(_:)``) says is in the background.
        /// Nil renders everything with `computeUnits`. The app sets `.cpu` here on a phone whose main
        /// set is on the GPU, which iOS forbids to a backgrounded app; the set loads after the main
        /// one, one stage at a time and only while the phone is cool.
        public var backgroundComputeUnits: KokoroComputeUnits?

        public init(punctuationSuppression: PunctuationSuppression = .allPunctuation, crossfadePieces: Bool = false,
                    removeTailClick: Bool = false, trimSeams: Bool = false, f0Spread: Float = 1,
                    computeUnits: KokoroComputeUnits = .cpu, backgroundComputeUnits: KokoroComputeUnits? = nil) {
            self.punctuationSuppression = punctuationSuppression
            self.crossfadePieces = crossfadePieces
            self.removeTailClick = removeTailClick
            self.trimSeams = trimSeams
            self.f0Spread = f0Spread
            self.computeUnits = computeUnits
            self.backgroundComputeUnits = backgroundComputeUnits
        }

        /// What the app ships with — not this initializer's own defaults, which are upstream's. See
        /// the property docs above and `spikes/findings/2026-09-05-coreml-audio-quality.md`.
        public static let `default` = Options(
            punctuationSuppression: .none, crossfadePieces: true, removeTailClick: true, trimSeams: true
        )
    }

    private let resources: KokoroCoreMLResources.Located
    public private(set) var options: Options
    private var loaded: Loaded?
    /// The stage compile in flight, if one is. See ``compiledStages()`` for why it is shared.
    private var compiling: Task<[String: URL], Error>?
    /// The concurrent stage load in flight, if one is: shared for the same reason as the compile.
    private var loadingStages: Task<KokoroCoreMLModels.LoadedStages, Error>?
    /// Told `(loaded, total)` as each stage's compute plan finishes building; the app's launch
    /// warm-up sets it so the reader can watch the one-time load go by rather than wait blind.
    private var loadProgress: (@Sendable (Int, Int) -> Void)?
    /// Awaited before each stage's compute plan is built: the app's foreground gate (see
    /// `KokoroCoreMLModels.loadStages`). Nil admits every load at once, which is what the tests want.
    private var loadAdmission: (@Sendable () async -> Void)?
    /// Every stage loaded so far, ready set and later buckets together, so a later bucket's stages
    /// can be merged into a fuller provider.
    private var allStages: KokoroCoreMLModels.LoadedStages?
    /// The buckets `loaded.models` vends right now, ascending.
    private(set) var loadedBuckets: [Int] = []
    /// The duration models `loaded.models` vends right now, ascending: t128 at readiness, t256 once
    /// its plan is built (`loadLaterBuckets`). Pieces are cut at the largest minus the two frame ids.
    private(set) var loadedDurationTokenLengths: [Int] = []
    /// The load of the buckets after the ready set, once it has started; `awaitFullLoad()` joins it.
    private var laterBucketsTask: Task<Void, Error>?
    /// Where a render is placed, as the app sees it (`setRenderPlacement`): in front, or not.
    public enum RenderPlacement: Sendable, Hashable {
        case foreground
        case background
    }

    /// Asked before every piece; nil places everything in the foreground.
    private var renderPlacement: (@Sendable () -> RenderPlacement)?
    /// The background set (`Options.backgroundComputeUnits`), once loaded, and its load.
    private var backgroundLoaded: Loaded?
    private var backgroundLoadTask: Task<Void, Never>?
    /// When the background set's load last failed, so a retry can wait out
    /// ``backgroundSetLoadRetryInterval`` instead of trying again at once; `nil` before any failure
    /// and after a successful load. Not set on cancellation — a cancelled load is not a failure and
    /// may be retried immediately (the review of 2026-09-11, §3 R6).
    private var backgroundSetLoadFailedAt: ContinuousClock.Instant?
    /// How long after a failed background-set load ``renderSet(main:)`` and ``awaitBackgroundSet()``
    /// wait before trying again — 30 s in the app; a `var` rather than a `let` only so a test can
    /// shorten it and not pay the real 30 s (the review of 2026-09-11, §3 R6, §5 item 4).
    private var backgroundSetLoadRetryInterval: Duration = .seconds(30)
    /// The compiled stage URLs from the load that first called ``startBackgroundSetLoad(compiled:)``,
    /// kept so a retry has them to call it again with — `load()` only passes them once, at readiness.
    private var compiledStageURLs: [String: URL]?
    /// `KokoroCoreMLModels.loadStages(_:names:computeUnits:window:admission:onStageLoaded:)`, as
    /// ``startBackgroundSetLoad(compiled:)`` calls it: the real function by default. Settable by a
    /// test so a background-set load can be made to fail once and then succeed, to prove the retry
    /// (the review of 2026-09-11, §3 R6) without a real, transient Core ML failure to wait for.
    private var stageLoader: @Sendable (
        _ compiled: [String: URL], _ names: [String], _ computeUnits: KokoroComputeUnits, _ window: Int,
        _ admission: (@Sendable () async -> Void)?, _ onStageLoaded: (@Sendable (_ name: String, _ seconds: Double) -> Void)?
    ) async throws -> KokoroCoreMLModels.LoadedStages = KokoroCoreMLModels.loadStages
    /// The set the last piece rendered through, for the tests: "main" or "background".
    private(set) var lastRenderSet = "main"
    /// How many pipeline calls have run to completion — one per `kokoro call:` timing line, whether
    /// its audio was kept or thrown away by a `tooManyTokens`/`audioTruncated` retry. Internal, for
    /// the test that proves ``backgroundPieceTokenCount`` leaves no call to discard (the review of
    /// 2026-09-11, §5 item 2): a discarded call makes this exceed the utterance trace's piece count.
    private(set) var renderCallCount = 0
    /// The first-prediction warm-up started at readiness, and one per later bucket as it lands.
    private var predictorWarmUp: Task<Void, Never>?
    private var laterPredictorWarmUps: [Task<Void, Never>] = []
    /// What the warm-up has run so far, e.g. `duration_t128`, `bucket_3s`. Internal for the tests.
    private(set) var warmedPredictors: [String] = []
    /// Stages loaded, tallied across both phases for the warm-up's veil and for the one line that
    /// says what the load cost (`KokoroLoadTally`). A lock rather than actor state because the
    /// loader reports from its task group, off the actor.
    private let mainLoadTally = OSAllocatedUnfairLock(initialState: KokoroLoadTally(label: "main set", total: 0))
    /// `kokoro.timing`: every stage load, every pipeline call and every utterance, with its seconds —
    /// the measurement the performance audit's §8 asks for, read with
    /// `log stream --predicate 'subsystem == "com.t2s.reader" AND category == "kokoro.timing"'`.
    static let timingLog = Logger(subsystem: "com.t2s.reader", category: "kokoro.timing")
    /// Whether the timing lines are also written to stderr: launched with `-kokoro.timingConsole YES`
    /// (a user default, so the argument domain sets it). `devicectl device process launch --console`
    /// carries a phone's stderr but not its `os_log`, and the phone refuses a network syslog
    /// connection (2026-09-10), so this is how a launch from the Mac is watched. Read once, and
    /// SIGPIPE ignored with it: that console goes away when the phone locks, and a write to it must
    /// end the mirror, not the process.
    static let wantsTimingConsole: Bool = {
        let on = UserDefaults.standard.bool(forKey: "kokoro.timingConsole")
        if on { signal(SIGPIPE, SIG_IGN) }
        return on
    }()
    /// Set by the first write that fails, after which the console is never written again.
    private static let consoleLost = OSAllocatedUnfairLock(initialState: false)
    static var mirrorsTimingToConsole: Bool { wantsTimingConsole && !consoleLost.withLock { $0 } }

    /// The timing lines, on the phone, under the app's caches directory
    /// (`Library/Caches/kokoro-timing.log`; every launch appends under its own header, and a file
    /// past `KokoroTimingLog.capBytes` is first moved aside to `.1`): what any run leaves behind
    /// for `devicectl device copy from --domain-type appDataContainer`, whoever launched it and
    /// however it ended — the first launch's stage loads included, after the second. -1 when it
    /// could not be opened.
    private static let timingFileDescriptor: Int32 = {
        #if os(iOS)
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return -1 }
        return KokoroTimingLog.open(path: caches.appending(path: "kokoro-timing.log").path(percentEncoded: false))
        #else
        return -1
        #endif
    }()

    /// One timing line: to `kokoro.timing`, to the launch's file, and to stderr while
    /// ``mirrorsTimingToConsole``. POSIX writes, never `FileHandle`: on 2026-09-10 the first render
    /// after the phone locked — the console `devicectl` had attached gone with it — died in
    /// `FileHandle.write(_:)`, which raises an Objective-C exception no Swift catch can take.
    public static func timing(_ line: String) {
        timingLog.notice("\(line, privacy: .public)")
        let stamped = Array((timestamp() + " " + line + "\n").utf8)
        stamped.withUnsafeBufferPointer { buffer in
            if timingFileDescriptor >= 0 { _ = Darwin.write(timingFileDescriptor, buffer.baseAddress, buffer.count) }
            if mirrorsTimingToConsole, Darwin.write(STDERR_FILENO, buffer.baseAddress, buffer.count) < 0 {
                consoleLost.withLock { $0 = true }
            }
        }
    }

    /// Wall-clock "HH:mm:ss.SSS", so a pulled file reads against the phone's own crash and cache times.
    private static func timestamp() -> String {
        var now = timeval()
        gettimeofday(&now, nil)
        var seconds = time_t(now.tv_sec)
        var parts = tm()
        localtime_r(&seconds, &parts)
        return String(format: "%02d:%02d:%02d.%03d", parts.tm_hour, parts.tm_min, parts.tm_sec, Int(now.tv_usec) / 1000)
    }

    /// `x` with `digits` decimals, for the timing lines.
    public static func fixed(_ x: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", x) }
    /// How many times this engine has begun loading its stages. Internal for one test: "loaded once"
    /// and "compiled and loaded twice" differ only in this number and several minutes of Core ML.
    private(set) var loadCount = 0
    /// Whether the American G2P has been built. Internal for one test: `preload()` must build it, or
    /// the first sentence of a session pays for two lexicons and a network after the tap.
    var isG2PLoaded: Bool { americanG2P != nil }
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
        // Before any MLX array exists in the process: the default it resolves once is the CPU.
        _ = Self.mlxPinnedToCPU
    }

    /// Changes the post-processing for every render from here on. Internal, for the audio probe:
    /// it renders one passage under several settings, and a second engine would mean a second copy
    /// of the loaded stages. The app decides its options once, at construction.
    func setOptions(_ options: Options) {
        self.options = options
    }

    /// Diagnostic trace of one `synthesize` call, for the quality probe
    /// (`Tests/T2SKokoroTests/CoreML/KokoroQualityProbe.swift`): the Misaki tokens, the ids they
    /// became and every rendered piece with its duration frames and its offset in the joined audio —
    /// enough to place any sample of the output on the token that owns it and to find the seams.
    /// Internal and never set by the app.
    struct UtteranceTrace: Sendable {
        struct Word: Sendable {
            var text: String
            var phonemes: String?
            var whitespace: String
        }
        struct Piece: Sendable {
            var ids: [Int32]
            var owners: [Int]
            /// `KokoroPipeline.SynthesisResult.tokenDurationFrames`: one per framed id (BOS + ids + EOS).
            var frames: [Int]
            /// Where the piece's untrimmed audio would have begun in the joined output — what the fold
            /// counts BOS frames from; negative-shifted by the lead-in a seam trim dropped.
            var offsetSamples: Int
            /// Where the piece's audio actually begins in the joined output: the seam.
            var audioStartSamples: Int
            var sampleCount: Int
            var bucketSeconds: Int
        }
        var words: [Word]
        var phonemes: String
        var ids: [Int32]
        var owners: [Int]
        var pieces: [Piece]
    }
    private var utteranceTrace: (@Sendable (UtteranceTrace) -> Void)?

    /// Installs (or removes) the diagnostic trace. Tests only.
    func setUtteranceTrace(_ trace: (@Sendable (UtteranceTrace) -> Void)?) {
        utteranceTrace = trace
    }

    /// Loads every stage, compiling them first when the staging is not precompiled, the
    /// vocoder weights, and the American G2P. `synthesize` calls it lazily on first use; a caller
    /// that would rather pay the seconds before playback starts can call it itself.
    public func preload() async throws {
        _ = try await load()
    }

    /// Installs (or removes) the stage-load progress report; see ``loadProgress``.
    public func setLoadProgress(_ report: (@Sendable (_ loaded: Int, _ total: Int) -> Void)?) {
        loadProgress = report
    }

    /// Installs (or removes) the gate every stage load waits on before it starts; see ``loadAdmission``.
    public func setLoadAdmission(_ admit: (@Sendable () async -> Void)?) {
        loadAdmission = admit
    }

    /// Installs (or removes) the placement every piece asks before it renders. With a background
    /// set (`Options.backgroundComputeUnits`) a piece placed in the background renders through it;
    /// while that set is still loading, the piece waits on the load admission — the app's foreground
    /// gate — rather than render where iOS will refuse the work.
    public func setRenderPlacement(_ placement: (@Sendable () -> RenderPlacement)?) {
        renderPlacement = placement
    }

    /// Waits for the background set, if the options ask for one and its load has begun, and says
    /// whether the engine can now render in the background: the set is there, or none was asked for.
    /// A failed load is not final for the session (the review of 2026-09-11, §3 R6): once the wait
    /// for it finds no set and nothing in flight, a retry is kicked (``retryBackgroundSetLoadIfDue()``)
    /// and awaited too, so a caller that lands here after the retry window sees the second attempt.
    @discardableResult
    public func awaitBackgroundSet() async -> Bool {
        await backgroundLoadTask?.value
        if backgroundLoaded == nil { retryBackgroundSetLoadIfDue() }
        await backgroundLoadTask?.value
        return options.backgroundComputeUnits == nil || backgroundLoaded != nil
    }

    /// Whether the background set is loaded.
    public var hasBackgroundSet: Bool { backgroundLoaded != nil }

    /// Installs the function ``startBackgroundSetLoad(compiled:)`` calls in place of
    /// `KokoroCoreMLModels.loadStages`. Internal, for the test that proves a failed background-set
    /// load retries (the review of 2026-09-11, §3 R6): a fake that throws once and then defers to
    /// the real loader stands in for a real, transient Core ML failure.
    func setStageLoader(_ loader: @escaping @Sendable (
        _ compiled: [String: URL], _ names: [String], _ computeUnits: KokoroComputeUnits, _ window: Int,
        _ admission: (@Sendable () async -> Void)?, _ onStageLoaded: (@Sendable (_ name: String, _ seconds: Double) -> Void)?
    ) async throws -> KokoroCoreMLModels.LoadedStages) {
        stageLoader = loader
    }

    /// Installs how long a failed background-set load is held before ``renderSet(main:)`` or
    /// ``awaitBackgroundSet()`` retries it; see ``backgroundSetLoadRetryInterval``. Internal, for
    /// the same test as ``setStageLoader(_:)`` — it shortens the wait so the suite does not pay the
    /// real 30 s.
    func setBackgroundSetLoadRetryInterval(_ interval: Duration) {
        backgroundSetLoadRetryInterval = interval
    }

    /// Waits for the whole set: the main load, started here when it has not begun, and then the
    /// buckets and duration models that land after the ready set. `preload()` returns at readiness;
    /// a caller that wants to render in every bucket calls this, and gets the same set whether or
    /// not it preloaded first.
    ///
    /// Starting the load rather than only joining one already in flight is what makes this a
    /// barrier. On an engine nothing has loaded yet, `laterBucketsTask` is still nil, and the old
    /// body returned at once: the caller then rendered against whatever part of the set its own
    /// first render had brought in, and a second render moments later saw a fuller one — a
    /// different piece cap and a different bucket for the same words, so the two disagreed on where
    /// the words fell (the streamed and whole renders of
    /// ``KokoroCoreMLEngineTests/streamsALongPassageInPiecesThatFoldToTheSameTimings()`` drifted
    /// 0.10-0.27 s apart; the run of 2026-09-11 19:40).
    public func awaitFullLoad() async throws {
        _ = try await load()
        try await laterBucketsTask?.value
    }

    /// The stage count for the veil and the log, one closure for both load phases; the last stage
    /// of the set brings the summary line with it.
    private func stageReporter() -> @Sendable (String, Double) -> Void {
        let tally = mainLoadTally, report = loadProgress
        return { name, seconds in
            let (loaded, total, summary) = tally.withLock { tally in
                let summary = tally.record(name, seconds: seconds)
                return (tally.loaded, tally.total, summary)
            }
            Self.timing("kokoro stage \(name) loaded in \(Self.fixed(seconds, 2)) s (\(loaded)/\(total))")
            if let summary { Self.timing(summary) }
            report?(loaded, total)
        }
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
            // The compile and the load are this function's suspensions, and the actor is released
            // across them, so a render that arrived meanwhile may have finished the whole load.
            // Building a second set of `MLModel`s would pay for every compute plan again and hold two
            // copies of the 119 MB (§7.3) until the first was dropped.
            if let loaded { return loaded }
            try Task.checkCancellation()
            let stages = try await loadedStages(compiled)
            if let loaded { return loaded }
            try Task.checkCancellation()

            let weights = try JSONDecoder().decode(HnsfWeights.self, from: Data(contentsOf: resources.hnsfWeights))
            // Synchronous, so from here to the assignment the actor is never released: no other
            // render can observe this engine mid-load. Ready with the smallest and the largest
            // bucket (`KokoroCoreMLResources.readyBuckets`); the rest follow on their own task
            // (`loadLaterBuckets`), each swapping in a fuller provider as it lands, so a cold
            // launch's first sound waits for eight plans, not fourteen.
            let loaded = Loaded(models: try KokoroCoreMLModels(stages: stages, buckets: KokoroCoreMLResources.readyBuckets,
                                                               durationTokenLengths: KokoroCoreMLResources.readyDurationTokenLengths),
                                linearWeights: weights.linear_weights,
                                linearBias: weights.linear_bias)
            self.loaded = loaded
            allStages = stages
            loadedBuckets = KokoroCoreMLResources.readyBuckets.sorted()
            loadedDurationTokenLengths = KokoroCoreMLResources.readyDurationTokenLengths.sorted()
            // The models live in `loaded` now; the task must not keep a second reference to them.
            loadingStages = nil
            // The G2P's lexicons (two 3 MB JSON files, merged) and its fallback network are the other
            // thing the first sentence would otherwise wait for; build the American one here so the
            // launch warm-up pays it. The British G2P stays lazy: a `b*` voice is a choice, not the
            // default, and its lexicon is another 9 MB.
            let g2pClock = ContinuousClock()
            let g2pStarted = g2pClock.now
            _ = g2p(british: false)
            Self.timing("kokoro g2p built in \(Self.fixed(Self.seconds(g2pClock.now - g2pStarted), 2)) s")
            loadLaterBuckets(compiled: compiled)
            startPredictorWarmUp()
            startBackgroundSetLoad(compiled: compiled)
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

    /// The stages loaded concurrently (`KokoroCoreMLModels.loadStages`), once however many renders
    /// ask at the same time — the same sharing as ``compiledStages()``, for the same reason. This is
    /// where a load begins in earnest, so `loadCount` counts here.
    private func loadedStages(_ compiled: [String: URL]) async throws -> KokoroCoreMLModels.LoadedStages {
        if let loadingStages { return try await loadingStages.value }
        loadCount += 1
        mainLoadTally.withLock { $0 = KokoroLoadTally(label: "main set", total: KokoroCoreMLResources.stageNames().count) }
        let report = stageReporter(), admission = loadAdmission, computeUnits = options.computeUnits
        let names = KokoroCoreMLResources.stageNames(buckets: KokoroCoreMLResources.readyBuckets,
                                                     durationTokenLengths: KokoroCoreMLResources.readyDurationTokenLengths)
        let task = Task {
            try await KokoroCoreMLModels.loadStages(compiled, names: names, computeUnits: computeUnits,
                                                    admission: admission, onStageLoaded: report)
        }
        loadingStages = task
        do {
            return try await task.value
        } catch {
            loadingStages = nil
            throw error
        }
    }

    /// Loads the buckets after the ready set, one bucket at a time and smallest first, under the same
    /// admission gate, and installs each into a fuller provider as it lands. A bucket that fails to
    /// load is logged and skipped: the engine keeps rendering in the buckets it has, splitting what
    /// does not fit them, rather than close the route over one plan.
    private func loadLaterBuckets(compiled: [String: URL]) {
        guard laterBucketsTask == nil else { return }
        let report = stageReporter(), admission = loadAdmission, computeUnits = options.computeUnits
        laterBucketsTask = Task { [weak self] in
            for bucket in KokoroCoreMLResources.laterBuckets {
                try Task.checkCancellation()
                let names = KokoroCoreMLResources.stageNames(buckets: [bucket], durationTokenLengths: [])
                do {
                    let stages = try await KokoroCoreMLModels.loadStages(
                        compiled, names: names, computeUnits: computeUnits, admission: admission, onStageLoaded: report
                    )
                    guard let self else { return }
                    try await self.install(bucket: bucket, stages: stages)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    Self.timing("kokoro bucket \(bucket) s failed to load: \(String(describing: error))")
                }
            }
            // The t256 duration model last: the buckets cost seconds on the A13, this plan minutes,
            // and until it lands a long piece is cut at what t128 can time.
            for tokens in KokoroCoreMLResources.laterDurationTokenLengths {
                try Task.checkCancellation()
                let names = KokoroCoreMLResources.stageNames(buckets: [], durationTokenLengths: [tokens])
                do {
                    let stages = try await KokoroCoreMLModels.loadStages(
                        compiled, names: names, computeUnits: computeUnits, admission: admission, onStageLoaded: report
                    )
                    guard let self else { return }
                    try await self.install(durationTokenLength: tokens, stages: stages)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    Self.timingLog.error("kokoro duration t\(tokens, privacy: .public) failed to load: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// Swaps in a provider over every bucket loaded so far, `bucket` now among them, and warms the
    /// new bucket's first prediction behind the swap.
    private func install(bucket: Int, stages: KokoroCoreMLModels.LoadedStages) throws {
        guard let loaded, let known = allStages else { return }
        let merged = known.merging(stages)
        let buckets = (loadedBuckets + [bucket]).sorted()
        self.loaded = Loaded(models: try KokoroCoreMLModels(stages: merged, buckets: buckets,
                                                            durationTokenLengths: loadedDurationTokenLengths),
                             linearWeights: loaded.linearWeights, linearBias: loaded.linearBias)
        allStages = merged
        loadedBuckets = buckets
        Self.timing("kokoro bucket \(bucket) s ready; buckets \(buckets.map(String.init).joined(separator: ","))")
        guard options.computeUnits != .cpu else { return }
        let admission = loadAdmission
        laterPredictorWarmUps.append(Task { [weak self] in
            await admission?()
            await self?.warmPredictors(tokens: [], buckets: [bucket])
        })
    }

    /// Swaps in a provider with one more duration model, `tokens` long, so pieces can be cut to it
    /// from the next utterance on, and warms its first prediction behind the swap.
    private func install(durationTokenLength tokens: Int, stages: KokoroCoreMLModels.LoadedStages) throws {
        guard let loaded, let known = allStages else { return }
        let merged = known.merging(stages)
        let lengths = (loadedDurationTokenLengths + [tokens]).sorted()
        self.loaded = Loaded(models: try KokoroCoreMLModels(stages: merged, buckets: loadedBuckets, durationTokenLengths: lengths),
                             linearWeights: loaded.linearWeights, linearBias: loaded.linearBias)
        allStages = merged
        loadedDurationTokenLengths = lengths
        Self.timing("kokoro duration t\(tokens) ready; pieces up to \(min(Self.maxPieceTokenCount, tokens - 2)) ids")
        guard options.computeUnits != .cpu else { return }
        let admission = loadAdmission
        laterPredictorWarmUps.append(Task { [weak self] in
            await admission?()
            await self?.warmPredictors(tokens: [tokens], buckets: [])
        })
    }

    /// Warms every ready stage's first prediction, in the order the first sentences need them: the
    /// t128 duration model and the 3 s bucket (a streamed head's first piece), then the 15 s bucket
    /// (its second) — one step per turn of the actor, so a render that arrives between steps runs
    /// before the next. t256 is warmed when it lands (`install(durationTokenLength:stages:)`). Under the foreground gate, like the loads: this
    /// is GPU work. GPU policies only: on the CPU a plan is ready the moment it loads.
    private func startPredictorWarmUp() {
        guard options.computeUnits != .cpu, predictorWarmUp == nil else { return }
        let admission = loadAdmission
        predictorWarmUp = Task { [weak self] in
            let steps: [(tokens: [Int], buckets: [Int])] = [([128], [3]), ([], [15])]
            for step in steps {
                if Task.isCancelled { return }
                await admission?()
                guard let self else { return }
                await self.warmPredictors(tokens: step.tokens, buckets: step.buckets)
            }
        }
    }

    private func warmPredictors(tokens: [Int], buckets: [Int]) {
        guard let loaded else { return }
        let clock = ContinuousClock(), started = clock.now
        let what = tokens.map { "duration_t\($0)" } + buckets.map { "bucket_\($0)s" }
        do {
            try warmKokoroStages(modelProvider: loaded.models, tokenLengths: tokens, buckets: buckets)
        } catch {
            Self.timing("kokoro predictor warm-up failed (\(what.joined(separator: ", "))): \(String(describing: error))")
            return
        }
        warmedPredictors += what
        Self.timing("kokoro predictors warmed: \(what.joined(separator: ", ")) in \(Self.fixed(Self.seconds(clock.now - started), 2)) s")
    }

    /// Loads the background set (`Options.backgroundComputeUnits`) after the main set and its
    /// predictor warm-up: one stage at a time, under the load admission, at utility priority, and
    /// only while the phone is not thermally serious — on the iPhone 17 Pro these are CPU plans the
    /// compiler takes minutes over, and they are built for a listener who is reading in front while
    /// the GPU renders. Every stage lands in Core ML's plan cache, so a launch that is backgrounded
    /// or killed mid-way resumes where it stopped. A failure is logged and the set stays absent for
    /// now — ``failedToLoadBackgroundSet(_:)`` clears the task and starts the retry clock, so a
    /// background render waits for the foreground rather than fail, and the session gets another
    /// attempt rather than none (the review of 2026-09-11, §3 R6).
    private func startBackgroundSetLoad(compiled: [String: URL]) {
        guard let units = options.backgroundComputeUnits, backgroundLoadTask == nil, backgroundLoaded == nil else { return }
        compiledStageURLs = compiled
        let admission = loadAdmission
        let stageLoader = stageLoader
        let names = KokoroCoreMLResources.stageNames(buckets: KokoroCoreMLResources.backgroundBuckets,
                                                     durationTokenLengths: KokoroCoreMLResources.backgroundDurationTokenLengths)
        let tally = OSAllocatedUnfairLock(initialState: KokoroLoadTally(label: "background set on \(units.runtimeName)", total: names.count))
        backgroundLoadTask = Task(priority: .utility) { [weak self] in
            await self?.awaitPredictorWarmUp()
            do {
                let stages = try await stageLoader(
                    compiled, names, units, 1,
                    {
                        await admission?()
                        await Self.waitWhileThermallySerious()
                    },
                    { name, seconds in
                        let (loaded, total, summary) = tally.withLock { tally in
                            let summary = tally.record(name, seconds: seconds)
                            return (tally.loaded, tally.total, summary)
                        }
                        Self.timing("kokoro background stage \(name) loaded in \(Self.fixed(seconds, 2)) s (\(loaded)/\(total)) on \(units.runtimeName)")
                        if let summary { Self.timing(summary) }
                    }
                )
                guard let self else { return }
                try await self.installBackgroundSet(stages)
            } catch is CancellationError {
                await self?.cancelledBackgroundSetLoad()
            } catch {
                await self?.failedToLoadBackgroundSet(error)
            }
        }
    }

    /// Clears the background load task after a cancellation, so the next call that wants the
    /// background set may start a fresh load at once: a cancellation is not a failure, so no retry
    /// delay applies (the review of 2026-09-11, §3 R6).
    private func cancelledBackgroundSetLoad() {
        backgroundLoadTask = nil
    }

    /// Clears the background load task and records when it failed, so ``retryBackgroundSetLoadIfDue()``
    /// starts a fresh load once ``backgroundSetLoadRetryInterval`` has passed instead of the set
    /// staying absent, and every later background piece parking on the gate, for the rest of the
    /// session (the review of 2026-09-11, §3 R6).
    private func failedToLoadBackgroundSet(_ error: Error) {
        backgroundLoadTask = nil
        backgroundSetLoadFailedAt = ContinuousClock().now
        Self.timing("kokoro background set failed to load: \(String(describing: error))")
    }

    /// Starts the background set's load again when the last attempt failed more than
    /// ``backgroundSetLoadRetryInterval`` ago and nothing is loading or loaded now. Without this,
    /// ``startBackgroundSetLoad(compiled:)``'s own guard — which only stops it running twice at
    /// once — leaves a failed load final for the session (the review of 2026-09-11, §3 R6). A no-op
    /// before the first load ever reaches `startBackgroundSetLoad` (``compiledStageURLs`` still nil).
    private func retryBackgroundSetLoadIfDue() {
        guard options.backgroundComputeUnits != nil, backgroundLoaded == nil, backgroundLoadTask == nil,
              let compiledStageURLs else { return }
        if let failedAt = backgroundSetLoadFailedAt, ContinuousClock().now - failedAt < backgroundSetLoadRetryInterval { return }
        startBackgroundSetLoad(compiled: compiledStageURLs)
    }

    private func installBackgroundSet(_ stages: KokoroCoreMLModels.LoadedStages) throws {
        guard let loaded else { return }
        backgroundLoaded = Loaded(
            models: try KokoroCoreMLModels(stages: stages, buckets: KokoroCoreMLResources.backgroundBuckets,
                                           durationTokenLengths: KokoroCoreMLResources.backgroundDurationTokenLengths),
            linearWeights: loaded.linearWeights, linearBias: loaded.linearBias
        )
        Self.timing("kokoro background set ready: buckets \(KokoroCoreMLResources.backgroundBuckets.map(String.init).joined(separator: ",")), duration t\(KokoroCoreMLResources.backgroundDurationTokenLengths.map(String.init).joined(separator: ","))")
    }

    /// Returns once the phone's thermal state is below serious, polling every 30 s while it is not,
    /// and logs the hold once as it begins and once as it ends: a hot phone can keep the background
    /// set from loading for many minutes, and the timing log should say so.
    static func waitWhileThermallySerious() async {
        var waitStarted: ContinuousClock.Instant?
        while [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) {
            if Task.isCancelled { return }
            if waitStarted == nil {
                waitStarted = ContinuousClock().now
                Self.timing("kokoro background set load held: the phone is thermally serious")
            }
            try? await Task.sleep(for: .seconds(30))
        }
        if let waitStarted {
            Self.timing("kokoro background set load resumed after \(Self.fixed(Self.seconds(ContinuousClock().now - waitStarted), 0)) s thermally serious")
        }
    }

    /// The set the next piece renders through. In front, the main set. In the background, the
    /// background set when there is one; until there is, ``retryBackgroundSetLoadIfDue()`` gets a
    /// fresh load started if the last one failed and enough time has passed, and the load admission
    /// — the app's foreground gate — is awaited, and the main set is used once the app is back in
    /// front. The wait is logged once as it begins and once as it ends, with the set it ended in: on
    /// the phone the timing log is what says whether a silence was this wait, the CPU budget, or a
    /// failed call.
    private func renderSet(main: Loaded) async throws -> Loaded {
        guard options.backgroundComputeUnits != nil, let placement = renderPlacement else { return main }
        var waitStarted: ContinuousClock.Instant?
        while placement() == .background {
            // The gate returns at once to a cancelled task, so without this a render cancelled while
            // the phone is locked — a stream its consumer stopped, a voice preview — would spin here
            // at full speed until the unlock (the review of 2026-09-11, R5).
            try Task.checkCancellation()
            if let backgroundLoaded {
                if let waitStarted {
                    Self.timing("kokoro piece placed in the background set after waiting \(Self.fixed(Self.seconds(ContinuousClock().now - waitStarted), 1)) s")
                }
                return backgroundLoaded
            }
            retryBackgroundSetLoadIfDue()
            guard let admission = loadAdmission else { return main }
            if waitStarted == nil {
                waitStarted = ContinuousClock().now
                Self.timing("kokoro piece placed in the background before the background set exists; waiting for the foreground")
            }
            await admission()
        }
        if let waitStarted {
            Self.timing("kokoro piece placed in the main set after waiting \(Self.fixed(Self.seconds(ContinuousClock().now - waitStarted), 1)) s for the foreground")
        }
        return main
    }

    /// `renderedPieces` through the set the placement chooses, rendering again where iOS allows it
    /// when the GPU refused a call that began as the app left the foreground. When the background
    /// set is what `renderSet` returns, `piece` — cut for the main set's bucket — is re-cut at
    /// ``backgroundPieceTokenCount`` first, so the 3 s bucket sees pieces sized for it instead of
    /// a full-size call that overflows, is halved and thrown away (the review of 2026-09-11, §2.3(b),
    /// §3 R2, §5 item 2). The re-cut's first sub-piece inherits `piece`'s own `cut` — the seam before
    /// it — the same rule ``splitPiece(groups:at:isFinal:words:inheriting:)`` uses for an
    /// overflow split; the sub-pieces after it already carry the right cut, computed the same way by
    /// ``pieces(ids:owners:words:cap:firstPieceCap:firstToken:extendToEnd:)`` itself.
    ///
    /// The offsets the re-cut counts each sub-piece's `phonemeUTF16Count` over are `piece`'s own,
    /// not the whole utterance's — see ``backgroundPieces(of:isFinal:words:)``.
    private func placedPieces(_ piece: Piece, isFinal: Bool, words: [MToken], tokenizer: KokoroTokenizer, main: Loaded, spread: Float)
        async throws -> [(piece: Piece, result: KokoroPipelineResult, audio: [Float])] {
        let set = try await renderSet(main: main)
        lastRenderSet = set.models === main.models ? "main" : "background"
        do {
            guard set.models !== main.models else {
                return try renderedPieces(piece, isFinal: isFinal, words: words, tokenizer: tokenizer, loaded: set, spread: spread)
            }
            let subPieces = try Self.backgroundPieces(of: piece, isFinal: isFinal, words: words)
            var rendered: [(piece: Piece, result: KokoroPipelineResult, audio: [Float])] = []
            for (index, subPiece) in subPieces.enumerated() {
                rendered += try renderedPieces(
                    subPiece, isFinal: isFinal && index == subPieces.count - 1, words: words, tokenizer: tokenizer,
                    loaded: set, spread: spread
                )
            }
            return rendered
        } catch KokoroCoreMLError.stageFailed(let reason) where set.models === main.models && renderPlacement?() == .background {
            Self.timing("kokoro call refused in the background; rendering again where it is allowed: \(reason.prefix(80))")
            let again = try await renderSet(main: main)
            lastRenderSet = again.models === main.models ? "main" : "background"
            return try renderedPieces(piece, isFinal: isFinal, words: words, tokenizer: tokenizer, loaded: again, spread: spread)
        }
    }

    /// `piece` — cut for the main set's bucket — re-cut at ``backgroundPieceTokenCount`` for the
    /// background set's 3 s one, with the voice-row lengths a cut of the whole utterance would have
    /// given the same words.
    ///
    /// The token offsets are `piece`'s own, not the utterance's: the first sub-piece counts from
    /// `piece`'s first owned Misaki token, and only a `piece` that really is the utterance's last
    /// (`isFinal`) lets its last sub-piece charge the trailing tokens that phonemized to no id at
    /// all. Left to the batch cutter's defaults — a `firstToken` of 0, and an `extendToEnd` on
    /// whichever piece happens to be last — the first sub-piece would be charged every word before
    /// `piece` and the last every word after it; since `KokoroTokenizer.refS` clamps to the voice
    /// table's rows, that pins nearly every background sub-piece of a long utterance to the same
    /// maxed-out style row, an audible prosody mismatch (the review of 2026-09-11 16:25). Only the
    /// first token is passed: the last sub-piece's own last group already carries `piece`'s last
    /// owned token, which is where it stops when `extendToEnd` is `false`.
    ///
    /// The first sub-piece inherits `piece`'s own `cut` — the seam before it; the ones after it are
    /// cut by ``pieces(ids:owners:words:cap:firstPieceCap:firstToken:extendToEnd:)`` itself.
    /// Internal rather than private so the offsets can be tested with no Core ML set at all.
    static func backgroundPieces(of piece: Piece, isFinal: Bool, words: [MToken]) throws -> [Piece] {
        var subPieces = try Self.pieces(
            ids: piece.ids, owners: piece.owners, words: words, cap: Self.backgroundPieceTokenCount,
            firstToken: piece.owners.first { $0 != KokoroCoreMLTimingFold.noOwner } ?? 0,
            extendToEnd: isFinal
        )
        if !subPieces.isEmpty { subPieces[0].cut = piece.cut }
        return subPieces
    }

    /// Waits for the predictor warm-up that readiness started and for every later bucket's. Tests.
    public func awaitPredictorWarmUp() async {
        await predictorWarmUp?.value
        for task in laterPredictorWarmUps { await task.value }
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }

    /// The compiled stage URLs, compiling the `.mlpackage` staging exactly once however many renders
    /// ask at the same time.
    ///
    /// `load()` suspends twice — here, while `MLModel.compileModel` runs, and in ``loadedStages(_:)``
    /// while the plans build — and the actor is released across both, so `load()` is reentrant. The
    /// recommended app wiring — `preload()` off the playback path, a render on play — is exactly the
    /// pattern that arrives twice: without sharing, both would compile and load a full set of stages,
    /// doubling the compute-plan build (206 s on an A13's first launch) and, briefly, the footprint.
    /// Each step is shared through one `Task`, and `load()` re-checks for a finished load after each
    /// suspension. The models cross the second suspension under one rule: nothing touches them until
    /// the whole set is back on this actor.
    private func compiledStages() async throws -> [String: URL] {
        if let compiling { return try await compiling.value }
        // Nothing to compile: Xcode ran `coremlc` at build time, so on the app's own staging this
        // function never suspends (`load()` still does, in `loadedStages`).
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

    /// What every render starts from: the voice checked, the stages loaded, the text phonemized and
    /// tokenized. Shared by `synthesize` and `stream`.
    private struct Prepared {
        let loaded: Loaded
        /// The delivery the route asks for, else the engine's own (`Options.f0Spread`, 1 by default).
        let spread: Float
        let tokenizer: KokoroTokenizer
        let words: [MToken]
        let phonemes: String
        let ids: [Int32]
        let owners: [Int]
        /// How long the G2P took, for the utterance's timing line.
        let g2pSeconds: Double
    }

    private func prepare(_ request: SynthesisRequest) async throws -> Prepared {
        guard let id = KokoroVoiceID(rawValue: request.voiceID), id.engineID == engineID else {
            throw KokoroCoreMLError.voiceNotForThisEngine(request.voiceID)
        }
        guard !request.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SynthesisError.failed("nothing to speak")
        }
        // The last chance to leave cheaply. The scheduler cancels pending renders on stop, and this
        // actor's queue is serial: without this, a cancelled render would still compile every stage
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
        let g2pClock = ContinuousClock()
        let g2pStarted = g2pClock.now
        let words = MLX.Device.withDefaultDevice(.cpu) {
            g2p(british: id.voice.hasPrefix("b")).phonemize(text: request.spoken).1
        }
        let g2pSeconds = Self.seconds(g2pClock.now - g2pStarted)
        let (phonemes, ownersByCharacter) = Self.phonemeWalk(words)
        let tokenization = tokenizer.tokenize(phonemes: phonemes, ownersByCharacter: ownersByCharacter)
        let spread = id.spread ?? options.f0Spread
        return Prepared(loaded: loaded, spread: spread, tokenizer: tokenizer, words: words, phonemes: phonemes,
                        ids: tokenization.ids, owners: tokenization.owners, g2pSeconds: g2pSeconds)
    }

    /// One line per utterance: the G2P's share, the pieces, the audio and the whole wall time.
    private static func logUtterance(_ path: String, g2pSeconds: Double, pieces: Int, audioSeconds: Double, since started: ContinuousClock.Instant) {
        let total = seconds(ContinuousClock().now - started)
        let rtf = audioSeconds > 0 ? total / audioSeconds : 0
        Self.timing("kokoro utterance (\(path)): g2p \(Self.fixed(g2pSeconds, 3)) s, \(pieces) pieces, audio \(Self.fixed(audioSeconds, 2)) s, total \(Self.fixed(total, 3)) s, RTF \(Self.fixed(rtf, 3))")
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> T2SCore.SynthesisResult {
        // Both checks come before the load, so a misrouted request costs nothing and the tests that
        // pin them need no model.
        let started = ContinuousClock().now
        let prepared = try await prepare(request)
        let loaded = prepared.loaded, tokenizer = prepared.tokenizer, words = prepared.words
        let phonemes = prepared.phonemes
        let tokenization = (ids: prepared.ids, owners: prepared.owners)

        let pieces = try Self.pieces(ids: tokenization.ids, owners: tokenization.owners, words: words,
                                     cap: Self.pieceCap(for: loaded))
        let spread = prepared.spread
        var samples: [Float] = []
        var folds: [KokoroCoreMLTimingFold.Piece] = []
        var tracedPieces: [UtteranceTrace.Piece] = []
        for (index, piece) in pieces.enumerated() {
            try Task.checkCancellation()
            // A piece whose predicted audio overflows its bucket is split and rendered in halves
            // rather than losing the sentence to 200 ms of silence (spec §6; Task 3,
            // `spikes/findings/2026-09-05-coreml-audio-quality.md`), so one piece from `pieces` may
            // become several rendered pieces here.
            let rendered = try await placedPieces(
                piece, isFinal: index == pieces.count - 1, words: words, tokenizer: tokenizer, main: loaded, spread: spread
            )
            for (subPiece, result, cleaned) in rendered {
                var previous = samples
                var next = cleaned
                var droppedHead = 0
                if options.trimSeams, !samples.isEmpty, subPiece.cut != .none {
                    // The head is never trimmed past the BOS token's own span, so the first word's
                    // fold time (offset + BOS frames) stays at or after the piece's first sample. The
                    // tail is silence the model rendered inside the previous piece's last frames; the
                    // fold clamps that piece's last word to what remains.
                    let bosSamples = (result.tokenDurationFrames.first ?? 0) * PipelineConstants.samplesPerDurationFrame
                    let trimmed = KokoroCoreMLSeam.trimmed(
                        previous: samples, next: cleaned, budget: KokoroCoreMLSeam.budgetSamples(for: subPiece.cut),
                        tailCap: .max, headCap: bosSamples
                    )
                    previous = trimmed.previous
                    next = trimmed.next
                    droppedHead = trimmed.droppedHead
                    if trimmed.droppedTail > 0, !folds.isEmpty {
                        folds[folds.count - 1].trimmedTailSeconds = Double(trimmed.droppedTail) / Double(PipelineConstants.sampleRate)
                    }
                }
                // With a crossfade the join overlaps the last 5 ms of the previous piece, so the
                // piece's audio starts that much earlier than a plain append would put it.
                let joined = options.crossfadePieces && !previous.isEmpty
                    ? PcmJoiner.join(segments: [previous, next], sampleRate: PipelineConstants.sampleRate)
                    : previous + next
                // Where the piece's untrimmed audio would have begun: the fold counts BOS frames from
                // here, and the dropped lead-in was inside them.
                let offsetSamples = joined.count - next.count - droppedHead
                folds.append(KokoroCoreMLTimingFold.Piece(
                    owners: subPiece.owners,
                    frames: result.tokenDurationFrames,
                    offsetSeconds: Double(offsetSamples) / Double(PipelineConstants.sampleRate)
                ))
                if utteranceTrace != nil {
                    tracedPieces.append(UtteranceTrace.Piece(
                        ids: subPiece.ids, owners: subPiece.owners, frames: result.tokenDurationFrames,
                        offsetSamples: offsetSamples, audioStartSamples: offsetSamples + droppedHead,
                        sampleCount: next.count, bucketSeconds: result.bucketSeconds
                    ))
                }
                samples = joined
            }
        }

        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { throw KokoroCoreMLError.emptyAudio }
        utteranceTrace?(UtteranceTrace(
            words: words.map { UtteranceTrace.Word(text: $0.text, phonemes: $0.phonemes, whitespace: $0.whitespace) },
            phonemes: phonemes, ids: tokenization.ids, owners: tokenization.owners, pieces: tracedPieces
        ))
        let audio = PCMAudio(sampleRate: Double(PipelineConstants.sampleRate), samples: samples)
        let timed = KokoroCoreMLTimingFold.timedTokens(
            words.map { KokoroToken(text: $0.text, whitespace: $0.whitespace, start: nil, end: nil) },
            pieces: folds
        )
        Self.logUtterance("whole", g2pSeconds: prepared.g2pSeconds, pieces: folds.count, audioSeconds: audio.duration, since: started)
        return T2SCore.SynthesisResult(
            audio: audio,
            wordTimings: KokoroTokenTimingMapper.map(timed, spoken: request.spoken, duration: audio.duration)
        )
    }

    public nonisolated func synthesizeStreaming(_ request: SynthesisRequest) -> AsyncThrowingStream<SynthesisChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.stream(request) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `synthesize` in pieces, each finalized on its own — tail click gone, tail silence cut to the
    /// budget of the cut that follows it, lead-in cut up to its BOS frames — and emitted the moment
    /// it is, so the first sound needs the first small piece only (Plan 14). The pieces are butted,
    /// not crossfaded: with both sides trimmed the join lands inside silence. The timings are folded
    /// over the concatenation, exactly as `synthesize` folds over its join.
    private func stream(_ request: SynthesisRequest, emit: @Sendable (SynthesisChunk) -> Void) async throws {
        let started = ContinuousClock().now
        let prepared = try await prepare(request)
        let pieces = try Self.pieces(ids: prepared.ids, owners: prepared.owners, words: prepared.words,
                                     cap: Self.pieceCap(for: prepared.loaded), firstPieceCap: Self.streamingFirstPieceTokenCount)
        let rate = PipelineConstants.sampleRate
        var folds: [KokoroCoreMLTimingFold.Piece] = []
        var emittedSamples = 0
        var ordinal = 0
        // Every rendered sub-piece, in order, waiting for the cut after it to be known.
        var pending: [(piece: Piece, result: KokoroPipelineResult, audio: [Float])] = []

        /// Emits `pending[k]`, whose successor's cut is `next` (nil for the utterance's last).
        func emitPiece(_ k: Int, next: KokoroCoreMLSeam.Cut?) throws {
            let (piece, result, cleaned) = pending[k]
            var audio = cleaned
            var droppedHead = 0
            var droppedTail = 0
            if options.trimSeams {
                if piece.cut != .none {
                    let bosSamples = (result.tokenDurationFrames.first ?? 0) * PipelineConstants.samplesPerDurationFrame
                    (audio, droppedHead) = KokoroCoreMLSeam.trimmedHead(audio, cap: bosSamples)
                }
                if let next {
                    (audio, droppedTail) = KokoroCoreMLSeam.trimmedTail(audio, budget: KokoroCoreMLSeam.budgetSamples(for: next))
                }
            }
            guard !audio.isEmpty, audio.allSatisfy(\.isFinite) else { throw KokoroCoreMLError.emptyAudio }
            // Where the piece's untrimmed audio would have begun: the fold counts BOS frames from
            // here, and the dropped lead-in was inside them.
            folds.append(KokoroCoreMLTimingFold.Piece(
                owners: piece.owners, frames: result.tokenDurationFrames,
                offsetSeconds: Double(emittedSamples - droppedHead) / Double(rate),
                trimmedTailSeconds: Double(droppedTail) / Double(rate)
            ))
            emit(.piece(PCMAudio(sampleRate: Double(rate), samples: audio), ordinal: ordinal, isLast: next == nil))
            emittedSamples += audio.count
            ordinal += 1
        }

        for (index, piece) in pieces.enumerated() {
            try Task.checkCancellation()
            pending += try await placedPieces(
                piece, isFinal: index == pieces.count - 1, words: prepared.words, tokenizer: prepared.tokenizer, main: prepared.loaded,
                spread: prepared.spread
            )
            // A sub-piece is final once the cut after it is known — as soon as the next sub-piece
            // exists, or now for the utterance's last. Emit everything that qualifies.
            let isUtteranceLast = index == pieces.count - 1
            let emittable = isUtteranceLast ? pending.count : pending.count - 1
            for k in 0 ..< emittable {
                try emitPiece(k, next: k + 1 < pending.count ? pending[k + 1].piece.cut : nil)
            }
            pending.removeFirst(emittable)
        }
        guard emittedSamples > 0 else { throw KokoroCoreMLError.emptyAudio }
        Self.logUtterance("streamed", g2pSeconds: prepared.g2pSeconds, pieces: folds.count,
                          audioSeconds: Double(emittedSamples) / Double(rate), since: started)

        let timed = KokoroCoreMLTimingFold.timedTokens(
            prepared.words.map { KokoroToken(text: $0.text, whitespace: $0.whitespace, start: nil, end: nil) },
            pieces: folds
        )
        emit(.finished(wordTimings: KokoroTokenTimingMapper.map(
            timed, spoken: request.spoken, duration: Double(emittedSamples) / Double(rate)
        )))
    }

    /// One piece of an utterance rendered — split on overflow — with the tail click removed from
    /// every rendered sub-piece: what both `synthesize` and `stream` start from.
    private func renderedPieces(_ piece: Piece, isFinal: Bool, words: [MToken], tokenizer: KokoroTokenizer, loaded: Loaded, spread: Float)
        throws -> [(piece: Piece, result: KokoroPipelineResult, audio: [Float])] {
        try renderWithSplitting(piece, isFinal: isFinal, words: words, tokenizer: tokenizer, loaded: loaded, spread: spread).map { subPiece, result in
            (subPiece, result, options.removeTailClick ? KokoroCoreMLTailClick.removed(from: result.audio) : result.audio)
        }
    }

    /// One pipeline call. The duration models are static-shape, so the framed ids are padded with the
    /// boundary token and the mask with zeroes: `buildDurationInput` copies only what it is given
    /// into an `MLMultiArray` it does not zero. Padding to the *largest* staged model and letting
    /// `selectDurationChoice` pick the smallest that fits is safe either way — it copies a prefix of
    /// the padded ids, and the mask's zeroes tell it where the real tokens end.
    private func render(_ piece: Piece, tokenizer: KokoroTokenizer, loaded: Loaded, spread: Float) throws -> KokoroPipelineResult {
        let framed = [KokoroTokenizer.boundary] + piece.ids + [KokoroTokenizer.boundary]
        let padding = loaded.models.maxDurationTokenLength - framed.count
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
                    punctuationSuppression: options.punctuationSuppression,
                    f0Spread: spread
                ),
                modelProvider: loaded.models,
                linearWeights: loaded.linearWeights,
                linearBias: loaded.linearBias,
                tensorDump: &tensorDump
            )
        } catch {
            // The pipeline's own error and never the request text: this string reaches logs.
            Self.timing("kokoro call failed: \(String(describing: error))")
            throw KokoroCoreMLError.stageFailed(String(describing: error))
        }
        let t = result.timings
        let rtf = result.audioDurationSeconds > 0 ? result.wallTimeSeconds / result.audioDurationSeconds : 0
        renderCallCount += 1
        Self.timing("kokoro call: bucket \(result.bucketSeconds) s, audio \(Self.fixed(result.audioDurationSeconds, 2)) s, wall \(Self.fixed(result.wallTimeSeconds, 3)) s, RTF \(Self.fixed(rtf, 3)); duration \(Self.fixed(t.durationCoreML, 3)), f0 \(Self.fixed(t.f0ntrainCoreML, 3)), pre \(Self.fixed(t.decoderPre, 3)), hnsf \(Self.fixed(t.hnsfSwift, 3)) (overlap \(Self.fixed(t.decoderPreHnsfOverlap, 3))), gen \(Self.fixed(t.generatorCoreML, 3)), trim \(Self.fixed(t.trim, 3)); set \(lastRenderSet)")

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
        _ piece: Piece, isFinal: Bool, words: [MToken], tokenizer: KokoroTokenizer, loaded: Loaded, spread: Float
    ) throws -> [(piece: Piece, result: KokoroPipelineResult)] {
        do {
            // A set whose largest duration model is smaller than the piece — the background set's
            // t128 against a piece cut for t256 — splits it the way an overflowing bucket does.
            guard piece.ids.count + 2 <= loaded.models.maxDurationTokenLength else {
                throw KokoroCoreMLError.tooManyTokens(piece.ids.count + 2)
            }
            return [(piece, try render(piece, tokenizer: tokenizer, loaded: loaded, spread: spread))]
        } catch let error as KokoroCoreMLError {
            switch error {
            case .audioTruncated, .tooManyTokens: break
            default: throw error
            }
            let groups = Self.groups(ids: piece.ids, owners: piece.owners)
            guard groups.count > 1 else { throw error }
            let cutIndex = Self.middleCutIndex(in: groups)
            let (first, second) = Self.splitPiece(groups: groups, at: cutIndex, isFinal: isFinal, words: words, inheriting: piece.cut)
            return try renderWithSplitting(first, isFinal: false, words: words, tokenizer: tokenizer, loaded: loaded, spread: spread)
                + (try renderWithSplitting(second, isFinal: isFinal, words: words, tokenizer: tokenizer, loaded: loaded, spread: spread))
        }
    }

    /// The same recursion as ``renderWithSplitting(_:isFinal:words:tokenizer:loaded:)``, over an
    /// injected render call instead of the real pipeline. `static`, and so not actor-isolated: it
    /// touches no engine state — only `piece`'s own ids and owners, plus `words` for the halves'
    /// `phonemeUTF16Count` — so a test can call it directly, on any machine, with a fake `renderOne`
    /// that makes the first attempt throw ``KokoroCoreMLError/audioTruncated`` and asserts the
    /// halves that follow, without a real Core ML stage or any actor-isolation ceremony.
    static func renderSplittingOnOverflow(
        _ piece: Piece, isFinal: Bool, words: [MToken], maxTokens: Int = .max, render renderOne: RenderPiece
    ) throws -> [(piece: Piece, result: KokoroPipelineResult)] {
        do {
            guard piece.ids.count + 2 <= maxTokens else { throw KokoroCoreMLError.tooManyTokens(piece.ids.count + 2) }
            return [(piece, try renderOne(piece))]
        } catch let error as KokoroCoreMLError {
            switch error {
            case .audioTruncated, .tooManyTokens: break
            default: throw error
            }
            let groups = Self.groups(ids: piece.ids, owners: piece.owners)
            guard groups.count > 1 else { throw error }
            let cutIndex = Self.middleCutIndex(in: groups)
            let (first, second) = Self.splitPiece(groups: groups, at: cutIndex, isFinal: isFinal, words: words, inheriting: piece.cut)
            return try renderSplittingOnOverflow(first, isFinal: false, words: words, maxTokens: maxTokens, render: renderOne)
                + (try renderSplittingOnOverflow(second, isFinal: isFinal, words: words, maxTokens: maxTokens, render: renderOne))
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
        groups: [Group], at cutIndex: Int, isFinal: Bool, words: [MToken], inheriting cut: KokoroCoreMLSeam.Cut
    ) -> (first: Piece, second: Piece) {
        let firstGroups = groups[0 ... cutIndex]
        let secondGroups = groups[(cutIndex + 1)...]
        var (first, _) = Self.piece(
            from: firstGroups, firstToken: firstGroups.first?.token ?? 0, words: words, extendToEnd: false
        )
        first.cut = cut
        var (second, _) = Self.piece(
            from: secondGroups, firstToken: secondGroups.first?.token ?? 0, words: words, extendToEnd: isFinal
        )
        second.cut = Self.cut(after: groups[cutIndex])
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

    /// MLX's global default device set to the CPU, before anything of MLX runs. The task-local pin
    /// below was not enough on the iPhone 17 Pro: on 2026-09-10 16:16, with the phone locked
    /// mid-book, MLX's completion handler threw on `com.Metal.CompletionQueueDispatch` —
    /// "Insufficient Permission (to submit GPU work from background)" — so the fallback network had
    /// been running on the GPU under the pin, and iOS forbids GPU work from a backgrounded app. The
    /// MLX Kokoro route, closed and unmeasured, loses its GPU with this; nothing that ships does.
    private static let mlxPinnedToCPU: Void = {
        MLX.compile(enable: false)
        MLX.Device.setDefault(device: .cpu)
    }()

    /// The G2P for a language, built once and kept.
    ///
    /// MisakiSwift's out-of-lexicon fallback is a BART network on MLX, whose GEMMs are exactly what a
    /// pre-A14 GPU cannot run — so both the construction and every `phonemize` call are wrapped in
    /// `MLX.Device.withDefaultDevice(.cpu)`, a task-local, *and* `MLX.Device.setDefault(.cpu)` in
    /// `mlxPinnedToCPU` above: the task-local alone did not hold across MLX's Metal completion
    /// handler (the 16:16 abort, 2026-09-10), so the process-global default is the CPU too — the MLX
    /// Kokoro engine, which would want the GPU, is gated off beside this
    /// one in the app, where pinning the process to the CPU would cripple it (RTF 15).
    private func g2p(british: Bool) -> EnglishG2P {
        if let cached = british ? britishG2P : americanG2P { return cached }
        _ = Self.mlxPinnedToCPU
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
        /// How the piece before this one was closed — what the seam budget keys on. `.none` for the
        /// first piece of an utterance.
        var cut: KokoroCoreMLSeam.Cut = .none
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

    /// The kind of seam a piece that closes with `group` leaves behind it.
    private static func cut(after group: Group) -> KokoroCoreMLSeam.Cut {
        if groupEnds(group, with: KokoroVocabulary.sentenceFinalPunctuationTokenIds) { return .sentence }
        if groupEnds(group, with: KokoroVocabulary.clauseBoundaryPunctuationTokenIds) { return .clause }
        return .word
    }

    /// Where to close the current piece when the next group would overflow the cap: the last group
    /// in `current` that ends a sentence, else the last that ends a clause, else all of `current` —
    /// the cutter's original rule, kept as the last resort. A long sentence cut at a bare word and
    /// butted to the next left an audible seam; cutting where the duration model already predicts a
    /// pause hides it (`spikes/findings/2026-09-05-coreml-audio-quality.md`). The groups after the
    /// returned index start the next piece.
    private static func bestCutIndex(in current: [Group], cap: Int = maxPieceTokenCount) -> Int {
        // A boundary is only worth taking when the piece it closes is at least half a call's worth of
        // ids: a comma twenty ids into a 250-id sentence would otherwise make a tiny first piece and
        // three calls where two would do — and every call ends with Kokoro's long predicted tail.
        var idsThrough = 0
        var minimumIndex = current.count
        for (index, group) in current.enumerated() {
            idsThrough += group.ids.count
            if idsThrough * 2 >= cap { minimumIndex = index; break }
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
    /// start counting from. The range never runs backwards: a caller that seeds `firstToken` from
    /// the owners rather than from `groups` (``backgroundPieces(of:isFinal:words:)``) can hand in a
    /// token past a leading group that owns none, and one token's length is the right answer there
    /// rather than a trap.
    private static func piece(
        from groups: ArraySlice<Group>, firstToken: Int, words: [MToken], extendToEnd: Bool
    ) -> (piece: Piece, lastToken: Int) {
        var piece = Piece()
        for group in groups {
            piece.ids += group.ids
            piece.owners += group.owners
        }
        let lastToken = max(firstToken, extendToEnd ? words.count - 1 : (groups.last?.token ?? firstToken))
        piece.phonemeUTF16Count = (firstToken ... lastToken).reduce(0) {
            $0 + ((words[$1].phonemes ?? unknownPhoneme) + words[$1].whitespace).utf16.count
        }
        return (piece, lastToken)
    }

    /// The most ids a piece may carry for what `loaded` can time: the largest duration model's
    /// padded length minus the two frame ids, never above ``maxPieceTokenCount``.
    private static func pieceCap(for loaded: Loaded) -> Int {
        min(maxPieceTokenCount, loaded.models.maxDurationTokenLength - 2)
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
    /// `cap` is where a piece is cut: ``maxPieceTokenCount`` with every duration model loaded, what
    /// t128 can time before t256 lands (``pieceCap(for:)``). `firstPieceCap`, when given, caps the
    /// first piece only (a streamed head, Plan 14); every later piece is cut at `cap`.
    ///
    /// `firstToken` and `extendToEnd` place these ids inside the utterance for the voice-row lengths,
    /// and default to the whole of it: the first piece counts from Misaki token 0, and the last piece
    /// is charged the trailing tokens that phonemized to no id. A caller re-cutting one piece of an
    /// already-cut utterance passes that piece's own first token and whether it was the utterance's
    /// last — ``backgroundPieces(of:isFinal:words:)`` — so its sub-pieces get the counts the same
    /// words would have got from a cut of the whole utterance rather than counts stretched to both
    /// of its ends (the review of 2026-09-11 16:25).
    static func pieces(ids: [Int32], owners: [Int], words: [MToken], cap: Int = maxPieceTokenCount,
                       firstPieceCap: Int? = nil, firstToken: Int = 0, extendToEnd: Bool = true) throws -> [Piece] {
        let groups = Self.groups(ids: ids, owners: owners)

        var packed: [[Group]] = []
        var current: [Group] = []
        var currentCount = 0
        for group in groups {
            guard group.ids.count <= maxPieceTokenCount else {
                // One word longer than a whole pipeline input. Nothing to split it at.
                throw KokoroCoreMLError.tooManyTokens(group.ids.count)
            }
            // The cap for the piece being packed: the first piece's own when one was given, the usual
            // one after — re-read on every cut, since a cut is what fills `packed`.
            func capNow() -> Int { packed.isEmpty ? min(firstPieceCap ?? cap, cap) : cap }
            while currentCount + group.ids.count > capNow(), !current.isEmpty {
                let cutIndex = Self.bestCutIndex(in: current, cap: capNow())
                packed.append(Array(current[0 ... cutIndex]))
                current = Array(current[(cutIndex + 1)...])
                currentCount = current.reduce(0) { $0 + $1.ids.count }
            }
            current.append(group)
            currentCount += group.ids.count
        }
        if !current.isEmpty { packed.append(current) }

        // The pieces tile the Misaki tokens from `firstToken` on: every token's phonemized length is
        // charged to exactly one piece, including the tokens that survived the vocabulary with no id
        // at all, so the one-piece case reproduces the whole run's length.
        var pieces: [Piece] = []
        var nextToken = firstToken
        for (index, groupSlice) in packed.enumerated() {
            var (piece, lastToken) = Self.piece(
                from: groupSlice[...], firstToken: nextToken, words: words,
                extendToEnd: extendToEnd && index == packed.count - 1
            )
            if index > 0, let previousLast = packed[index - 1].last { piece.cut = Self.cut(after: previousLast) }
            pieces.append(piece)
            nextToken = lastToken + 1
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
