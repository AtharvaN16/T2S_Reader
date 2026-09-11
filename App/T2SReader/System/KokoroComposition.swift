// App/T2SReader/System/KokoroComposition.swift
#if KOKORO_ENGINE
import T2SKokoro
#endif
import Foundation
import Observation
import os
import OSLog
import T2SApp
import T2SAudio
import T2SCore

/// What Preferences shows for the Kokoro section. It describes the Core ML route — the one that runs
/// on every phone the app supports and therefore the one a reader has (spec §7.3).
enum KokoroStatus: Hashable, Sendable {
    /// The everyday build, which does not link the engine at all.
    case notLinked
    case checking
    /// The model is being downloaded and compiled (`KokoroCoreMLInstall`): the first launch after
    /// an install, once per install directory. `KokoroStatusModel.installProgress` has the numbers.
    case installing
    /// The launch warm-up is loading the stages. Reached before ``available`` on every launch of a
    /// build that has the model files.
    case preparing
    case available(isDebugOverride: Bool)
    case unavailable(String)

    /// True while the model is being installed or its stages are still loading — the one-time wait
    /// a fresh launch pays, up to minutes on an old phone. The playback UI shows this distinctly
    /// from routine buffering, which resolves in seconds regardless of launch state.
    var isWarming: Bool {
        switch self {
        case .checking, .installing, .preparing: true
        case .notLinked, .available, .unavailable: false
        }
    }
}

/// The install as the veil shows it. Declared here, outside `#if KOKORO_ENGINE`, so the model that
/// carries it compiles the same way in both builds; the Kokoro build maps the installer's own
/// progress onto it.
enum KokoroInstallProgress: Hashable, Sendable {
    /// Waiting for a network the download is allowed on (Wi-Fi).
    case waitingForNetwork(totalBytes: Int)
    case downloading(bytes: Int, totalBytes: Int)
    /// A refused or dropped file, tried again after `after` seconds; `fraction` holds the bar
    /// where the download was, so a retry does not read as the download starting over.
    case retrying(attempt: Int, of: Int, after: TimeInterval, fraction: Double)
    case compiling(stage: Int, totalStages: Int)

    /// 0…1 for the veil's bar.
    var fraction: Double {
        switch self {
        case .waitingForNetwork: 0
        case .downloading(let bytes, let total): total > 0 ? Double(bytes) / Double(total) : 0
        case .retrying(_, _, _, let fraction): fraction
        case .compiling(let stage, let total): total > 0 ? Double(stage) / Double(total) : 0
        }
    }
}

@MainActor
@Observable
final class KokoroStatusModel {
    private(set) var status: KokoroStatus
    /// A second footer line for the MLX route, or nil when there is nothing worth saying — which is
    /// every device where MLX is unavailable by construction (the simulator, a pre-A14 phone, a
    /// build with no weights staged). Two "not available" lines would only invite a reader to look
    /// for a second set of voices that is not there; the full reason is in the log either way.
    private(set) var mlxLine: String?
    /// The warm-up as the veil shows it: stages loaded over the total once the load has begun,
    /// when it started, and how long the last one on this phone took (nil before the first).
    private(set) var warmUpStages: (loaded: Int, total: Int)?
    private(set) var warmUpStarted: Date?
    private(set) var expectedWarmUpSeconds: Double?
    /// Set the moment a warm-up ends, cleared ``readyBeat`` seconds later: the last beat of the
    /// glow, which turns green before it goes (owner, 2026-09-10). One date in one model, so every
    /// copy of `WarmRamp` on screen — the veil, each ground bar — turns green on the same frame.
    private(set) var readyAt: Date?
    /// How long the green is held before the glow fades. Short: it is a confirmation, not a step.
    static let readyBeat: Double = 0.55
    private var readyBeatTask: Task<Void, Never>?
    /// `T2S_WARMUP=green` holds the beat instead of ending it, so it can be photographed.
    private static let holdsReadyBeat = ProcessInfo.processInfo.environment["T2S_WARMUP"] == "green"
    /// The install as it stands, while `status` is `.installing`.
    private(set) var installProgress: KokoroInstallProgress?
    /// Whether a foreground warm-up has built this install's compute plans (`KokoroWarmUpRecord`):
    /// what a background Prepare launch checks before it touches the engine. True in the everyday
    /// build, which has no plans to build.
    private(set) var warmedInstall: Bool
    /// True while the engine's background set is still compiling on a phone that needs one: the
    /// last part of the one-time setup, which only runs in front, so the screen stays awake for it.
    private(set) var isBuildingBackgroundSet = false

    init(_ status: KokoroStatus, warmedInstall: Bool = true) {
        self.status = status
        self.warmedInstall = warmedInstall
    }

    func update(_ status: KokoroStatus) {
        let wasWarming = self.status.isWarming
        self.status = status
        if case .preparing = status {
            warmUpStarted = Date()
            warmUpStages = nil
            expectedWarmUpSeconds = Self.storedWarmUpSeconds
        } else {
            warmUpStarted = nil
            warmUpStages = nil
        }
        if wasWarming, !status.isWarming { beginReadyBeat() }
        if case .installing = status {} else { installProgress = nil }
    }

    /// The green beat: `readyAt` now, cleared once it has been held, which is what takes the glow
    /// off the screen. Cancelling any beat already running keeps a second warm-up in the same
    /// launch (an install, then the stages) from cutting the first one's beat short.
    private func beginReadyBeat() {
        readyBeatTask?.cancel()
        readyAt = Date()
        guard !Self.holdsReadyBeat else { return }
        readyBeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.readyBeat))
            guard !Task.isCancelled else { return }
            self?.readyAt = nil
        }
    }

    func updateWarmUp(loaded: Int, total: Int) {
        warmUpStages = (loaded, total)
    }

    func updateInstall(_ progress: KokoroInstallProgress) {
        // A retry keeps the bar where the last byte left it; the installer does not know the bar.
        if case .retrying(let attempt, let of, let after, _) = progress {
            installProgress = .retrying(attempt: attempt, of: of, after: after, fraction: installProgress?.fraction ?? 0)
        } else {
            installProgress = progress
        }
    }

    func updateBackgroundSet(building: Bool) {
        isBuildingBackgroundSet = building
    }

    func markWarmedInstall() {
        warmedInstall = true
    }

    /// Remembered so the next launch's veil can say "about 6 s" instead of guessing. A first
    /// launch after install builds compute plans (minutes on an A13) and would mislead every
    /// later launch; the veil already knows a first launch by the absence of a stored number, so
    /// a duration that long is kept only if there was none before.
    func recordWarmUp(seconds: Double) {
        let previous = Self.storedWarmUpSeconds
        if let previous, seconds > previous * 4 { return }                   // a one-off stall, not the new normal
        UserDefaults.standard.set(seconds, forKey: Self.warmUpKey)
        expectedWarmUpSeconds = seconds
    }

    private static let warmUpKey = "kokoro.lastWarmUpSeconds"
    private static var storedWarmUpSeconds: Double? {
        let value = UserDefaults.standard.double(forKey: warmUpKey)
        return value > 0 ? value : nil
    }

    func updateMLXLine(_ line: String?) {
        mlxLine = line
    }
}

/// Everything the composition root needs from the Kokoro package, decided once per launch (spec
/// §3, plan adjustment 3). This is the app's only `#if KOKORO_ENGINE` apart from the two gated
/// engines beside it: the routes, the fallback resolver and the catalog are all pure types in the
/// root package, so every other file compiles the same way in both builds.
///
/// The Kokoro build links two runtimes, and they are different renders of the same words — different
/// engine identities, different render keys (spec §5). Core ML leads: it is CPU-only, so it runs
/// everywhere, and it is what "default" resolves to.
@MainActor
struct KokoroComposition {
    /// Every linked runtime's gated engine, in route order — `RoutedEngine` keys them by identity.
    /// Empty in the everyday build.
    let engines: [any SynthesisEngine]
    /// How `PlayerModel` and `PrepareRunner` decide a document's effective voice.
    let voiceRouting: any VoiceRouteResolving
    let status: KokoroStatusModel
    /// How far ahead the live player renders, in every state (the window is one value; the
    /// coordinator does not know the foreground from the background). Ten minutes on a phone whose
    /// main set is on the GPU (30 s of GPU at RTF 0.05), because it cannot render while locked
    /// until its CPU set has compiled — a first foreground session's work — and that set is slower.
    /// Three minutes on the CPU path: locked, the budget renders ~70 s of audio and then sleeps
    /// most of a minute (crashreport.md, Finding 2b), so a buffer the size of one cycle ran dry at
    /// every cycle's end; two cycles' worth (31 s of A13 rendering at RTF 0.17 to fill) rides
    /// through them.
    let playAheadWindowSeconds: TimeInterval?
    /// How far past the window the live player renders while the app is frontmost and the listener
    /// is listening: the rest of the current chapter, clamped to this range of audio seconds at 1x
    /// (Plan 18; `CoordinatorConfiguration.foregroundFill`). The point is the lock that follows:
    /// the budget-paced background loop sustains ~0.9 audio-seconds per wall-second at 1x on the
    /// A13 (crashreport.md, Finding 2b) — it can hold a buffer, never grow one — so the buffer is
    /// built while the screen is on, at RTF 0.17 and no budget, and the loop then finds its window
    /// already rendered. CPU path: 10–20 min, 2–11 min of A13 CPU per fill (RTF 0.17–0.56), 6–11 MB
    /// of AAC; a 20-minute buffer drains in ~3 h locked at 1x, ~33 min at 1.5x (deficit 0.6 s/s).
    /// GPU path: 20–60 min, 1–3 min of GPU at RTF 0.05, 34 MB at the most. Nil in the everyday
    /// build. Not rate-scaled — a CPU and disk spend, not a time-to-dry.
    let foregroundFillSeconds: ClosedRange<TimeInterval>?
    /// The runtimes whose voices the picker lists, with the qualifier each row carries — asked every
    /// time the list is drawn, because the MLX probe answers seconds after the composition root has
    /// finished. Returns an empty list in the everyday build.
    private let catalogEngines: @Sendable () -> [(identity: String, label: String)]

    /// Backs `noteScene(isBackground:)`; in the Kokoro build the same lock instance is captured by
    /// the placement closure passed to `GatedKokoroCoreMLEngine`, so a write here is what that
    /// closure sees on its next read. No default: a stored property with a default value but no
    /// explicit type annotation is excluded from the memberwise init entirely, which is how the
    /// Kokoro branch's `sceneIsBackground:` argument once went missing at the call site. Both build
    /// branches now pass their own instance — the everyday build's is never read.
    let sceneIsBackground: OSAllocatedUnfairLock<Bool>

    /// The user default that picks the compute units for the session (`KokoroComputeUnits`
    /// raw values: `cpu`, `cpuAndNeuralEngine`, `cpuAndGPU`, `all`); unset is `cpu`, the measured
    /// policy. A developer's switch for the audit's §3.7 measurement, not a setting.
    static let computeUnitsKey = "kokoro.computeUnits"
    /// The user default that bounds the foreground fill for the session, in audio seconds at 1x:
    /// `0` disables it, a positive value is its maximum (the minimum stays the path's own, or the
    /// value if that is smaller); unset is the path's policy. A developer's switch for the phone
    /// test and the first of Plan 18's three rollbacks — no rebuild — not a setting.
    static let foregroundFillKey = "render.foregroundFillMaxSeconds"

    /// The fill's range for the session: `policy` unless `override` says otherwise — nil for 0 or
    /// anything unusable, `min(policy.lowerBound, v)...v` for a positive `v`.
    nonisolated static func foregroundFill(policy: ClosedRange<TimeInterval>, override: Double?) -> ClosedRange<TimeInterval>? {
        guard let override else { return policy }
        guard override.isFinite, override > 0 else { return nil }
        return min(policy.lowerBound, override)...override
    }

    /// Adds the bundled Kokoro voices to the picker, in the build that has the engine.
    func catalog(wrapping base: any VoiceCatalog) -> any VoiceCatalog {
        // Whether Kokoro is linked at all is fixed at compile time; only which runtimes are listed
        // changes as the probes answer, and that is the catalog's own question from here on.
        guard !catalogEngines().isEmpty else { return base }
        return KokoroVoiceCatalog(base: base, engines: catalogEngines)
    }

    /// The fill's edges in the phone's timing log (`Library/Caches/kokoro-timing.log`), beside the
    /// engine's utterance lines, so a lock test can read where the fill stopped and what the window
    /// rendered after it (Plan 18 §4.1). Nothing in the everyday build.
    func noteFill(_ on: Bool) {
        #if KOKORO_ENGINE
        KokoroCoreMLEngine.timing("render-ahead fill \(on ? "on" : "off")")
        #endif
    }

    /// Set from `ScenePlacement.placesInBackground(phase:)`, not from the foreground gate: what the
    /// Core ML engine's placement closure reads to decide the main (GPU) set from the background
    /// (CPU) one. `.inactive` — Control Center, a notification banner, the app switcher — leaves
    /// this clear, so an interruption that never actually loses GPU submission does not park a
    /// streamed head on the background set's absence or force it into discarded 3 s-bucket pieces
    /// (2026-09-11 GPU-path review, §2.3, §5 item 3 — R4). The gate itself is untouched by this and
    /// keeps closing on anything but `.active`, because a plan build caught running once the app is
    /// actually backgrounded is killed for a minute of a core. A no-op in the everyday build, which
    /// links no engine that reads `sceneIsBackground`.
    func noteScene(isBackground: Bool) {
        sceneIsBackground.withLock { $0 = isBackground }
    }

    /// `gate` is the app's foreground gate: the install's compiles and the warm-up's compute-plan
    /// builds wait on it, because a process that is not frontmost is killed for a minute of a
    /// core (the iPhone 17 Pro, 2026-09-09 15:14). A process launched for a background task never
    /// opens it, so neither ever starts there.
    static func make(gate: ForegroundGate, defaults: UserDefaults = .standard) -> KokoroComposition {
        let log = Logger(subsystem: "com.t2s.reader", category: "kokoro")
        #if KOKORO_ENGINE
        // Where the downloaded model lives: the app's own Application Support, at a path that
        // survives reinstalls, so a reinstall never pays the download or the compile again.
        let applicationSupport = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                                appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let installRoot = KokoroCoreMLInstall.defaultRoot(applicationSupport: applicationSupport)
        // Presence-only and synchronous (spec §6): every file was checked against its digest when
        // it was staged or downloaded, so the answer for the Core ML route is already here, before
        // the first view is built.
        let coreML = KokoroCoreMLAvailabilityModel(bundle: .main, installRoot: installRoot)
        // By chip (`KokoroComputeUnits.defaultPolicy`): the A19 generation's CPU plan compiler never
        // finishes the big stages, so it gets the GPU; the A13 keeps the measured CPU path.
        let policy = KokoroComputeUnits.forThisDevice
        let requested = defaults.string(forKey: computeUnitsKey).flatMap(KokoroComputeUnits.init(rawValue:)) ?? policy
        // The override is held to the same memory floor as the policy: a 4 GB phone asked for the
        // GPU aborts in the plan compiler before the veil can say why.
        let computeUnits = KokoroComputeUnits.permitted(requested, physicalMemory: ProcessInfo.processInfo.physicalMemory)
        if computeUnits != requested {
            log.notice("Kokoro compute units \(requested.runtimeName, privacy: .public) refused on \(ProcessInfo.processInfo.physicalMemory / 1_000_000, privacy: .public) MB of memory; using \(computeUnits.runtimeName, privacy: .public)")
        }
        if computeUnits != policy {
            log.notice("Kokoro compute units overridden for this session: \(computeUnits.runtimeName, privacy: .public) (this phone's default is \(policy.runtimeName, privacy: .public))")
        }
        // The fill's bound by path (Plan 18): 10–20 min on the CPU path, 20–60 on the GPU's; the
        // developer default caps it or turns it off for the session. `double(forKey:)` reads a
        // launch argument's string as well as a stored number; the `object` test tells unset from 0.
        let fillPolicy: ClosedRange<TimeInterval> = computeUnits == .cpu ? 600...1200 : 1200...3600
        let fillOverride: Double? = defaults.object(forKey: foregroundFillKey) == nil ? nil : defaults.double(forKey: foregroundFillKey)
        let fill = Self.foregroundFill(policy: fillPolicy, override: fillOverride)
        if let fill {
            log.notice("render-ahead fill for this session: \(Int(fill.lowerBound), privacy: .public)–\(Int(fill.upperBound), privacy: .public) s of audio at 1x")
        } else {
            log.notice("render-ahead fill off for this session (\(foregroundFillKey, privacy: .public) = 0)")
        }
        // A main set on the GPU cannot render while the app is in the background — iOS refuses the
        // work — so such a phone keeps a small CPU set for what the gate says is in the background
        // (`KokoroCoreMLResources.backgroundBuckets`), loaded after the main one during the first
        // foreground session; until it exists, a background render waits for the foreground.
        let backgroundComputeUnits: KokoroComputeUnits? = computeUnits == .cpu ? nil : .cpu
        // Placement reads its own flag (`sceneIsBackground`, set by `noteScene(isBackground:)` from
        // `ScenePlacement`), not the gate: `.inactive` closes the gate (plan builds must not run
        // once the app is actually backgrounded a moment later) but must not place a streamed head
        // in the background too (2026-09-11 review §5 item 3, R4). `admission` stays the gate.
        // Starts `true` — background until a scene says otherwise. `RootPager`'s `onChange(of:
        // scenePhase, initial: true)` corrects it to the real phase on the first scene event, but a
        // process launched for a `BGProcessingTask` (`PrepareTaskOperation.run()`, its own
        // `AppEnvironment.live()`) never connects a scene at all, so this default is the only value
        // such a process ever sees — exactly the case the CPU background set exists for. `false`
        // here defaulted placement to the foreground's GPU main set, which a background process has
        // no GPU submission for, and the refusal-retry only fires from `.background` placement, so
        // it never caught this either (2026-09-11 GPU-path review, Task C).
        let sceneIsBackground = OSAllocatedUnfairLock(initialState: true)
        let coreMLEngine = GatedKokoroCoreMLEngine(availability: coreML, computeUnits: computeUnits,
                                                   backgroundComputeUnits: backgroundComputeUnits,
                                                   admission: { await gate.waitUntilForeground() },
                                                   placement: { sceneIsBackground.withLock { $0 } ? .background : .foreground })
        // The MLX route costs a 340 MB hash, so one probe per launch, started below and memoized —
        // the route's `isAvailable` joins this same work rather than starting a second.
        let mlx = KokoroAvailabilityModel(probe: .live(defaults: defaults))
        // The probe's answer, where the picker can read it. `VoiceCatalog.voices()` is nonisolated
        // and is called from off the main actor in the root package's tests, so the MLX model's
        // main-actor `state` cannot be the source — a lock can.
        let mlxListed = OSAllocatedUnfairLock(initialState: false)
        // What a background Prepare launch checks before it renders: whether a foreground warm-up
        // has built this install's compute plans (`KokoroWarmUpRecord`).
        let warmUpIdentity = KokoroWarmUpRecord.identity(
            bundlePath: Bundle.main.bundleURL.path(percentEncoded: false),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            modelsPath: installRoot.path(percentEncoded: false),
            revision: KokoroCoreMLResources.modelRevision
        )
        let status = KokoroStatusModel(.checking, warmedInstall: KokoroWarmUpRecord.isWarmed(identity: warmUpIdentity, defaults: defaults))
        // One generation of compute plans per install: iOS keys them on the install and never
        // removes the last install's, and the 11 Pro filled up under 4.36 GB of them (2026-09-11).
        // Here, before anything can load a stage, a cache built for another identity — or before
        // this record existed — goes; the warm-up below then builds this install's.
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let bundleIdentifier = Bundle.main.bundleIdentifier,
           let removed = KokoroPlanCache.prepare(for: warmUpIdentity, cachesDirectory: caches,
                                                 bundleIdentifier: bundleIdentifier, defaults: defaults) {
            log.notice("Kokoro plan cache wiped for a new install identity: \(removed / 1_048_576, privacy: .public) MB")
            KokoroCoreMLEngine.timing("kokoro plan cache wiped for a new install identity: \(removed / 1_048_576) MB")
        }

        // Whether the resolver may still route a document to Core ML. It starts as the presence
        // verdict — the files are there — and the warm-up may close it: a bundle whose stages will
        // never load must route documents *away* from Kokoro (spec §6, whole document) rather than
        // give a reader a book of 200 ms silences. Nothing reopens it before the next launch,
        // except an install finishing, which opens it for the first time.
        let coreMLRouteOpen = OSAllocatedUnfairLock(initialState: false)
        // `UserDefaults.standard` by name: `UserDefaults` is not `Sendable` to Swift 6, so the
        // parameter cannot be captured here, and the app never passes anything else.
        let markWarmed: @Sendable () -> Void = {
            KokoroWarmUpRecord.markWarmed(identity: warmUpIdentity, defaults: .standard)
            Task { @MainActor in status.markWarmedInstall() }
        }

        switch coreML.verdict {
        case .available(let decision, _):
            coreMLRouteOpen.withLock { $0 = true }
            log.notice("Kokoro Core ML route available (\(computeUnits.runtimeName, privacy: .public); the A13 measured RTF \(decision.measuredRTF, format: .fixed(precision: 3), privacy: .public))")
            // Loading the stages takes seconds on a modern phone and minutes on an A13's first
            // launch, and the G2P's lexicons a few hundred milliseconds more. Pay them now, while the
            // reader is still choosing a book, rather than at the first utterance — but only once the
            // scene is active: a background launch never builds a plan.
            status.update(.preparing)
            Task {
                await gate.waitUntilForeground()
                await warmUp(coreMLEngine, routeOpen: coreMLRouteOpen, status: status, log: log, markWarmed: markWarmed)
            }
        case .unavailable(.notInstalled(let missing)):
            log.notice("Kokoro Core ML model not installed (\(missing.errorDescription ?? "\(missing)", privacy: .public)); downloading")
            status.update(.installing)
            status.updateInstall(.waitingForNetwork(totalBytes: KokoroCoreMLManifest.totalByteCount))
            Task {
                await gate.waitUntilForeground()
                await install(into: installRoot, gate: gate, availability: coreML, engine: coreMLEngine,
                              routeOpen: coreMLRouteOpen, status: status, log: log, markWarmed: markWarmed)
            }
        case .unavailable(let reason):
            log.notice("Kokoro Core ML unavailable: \(reason.description, privacy: .public)")
            status.update(.unavailable(readerFacing(reason)))
        }

        Task {
            switch await mlx.resolve() {
            case .available(let decision, _):
                log.notice("Kokoro MLX route available (development override: \(decision.isDebugOverride, privacy: .public))")
                mlxListed.withLock { $0 = true }
                // Written after the box, and last: `KokoroStatusModel` is observed by the voice
                // list, so this line is also what redraws it with the MLX rows now in the catalog.
                status.updateMLXLine(decision.isDebugOverride
                    ? "MLX route: development override active."
                    : "MLX route: available (measured).")
            case .unavailable(let reason):
                log.notice("Kokoro MLX unavailable: \(reason.description, privacy: .public)")
                status.updateMLXLine(nil)
            }
        }

        return KokoroComposition(
            engines: [coreMLEngine, GatedKokoroEngine(availability: mlx)],
            voiceRouting: KokoroVoiceRouting(
                routes: [
                    KokoroVoiceRouting.Route(engineIdentity: KokoroCoreMLEngine.identity) {
                        coreMLRouteOpen.withLock { $0 }
                    },
                    KokoroVoiceRouting.Route(engineIdentity: KokoroEngine.identity) {
                        if case .available = await mlx.resolve() { return true }
                        return false
                    },
                ],
                // Spec §6: a reader who has never chosen a voice gets Kokoro Heart, not the system
                // voice — but only while the route that renders it is available.
                defaultVoice: KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: "af_heart").rawValue
            ),
            status: status,
            playAheadWindowSeconds: computeUnits == .cpu ? 180 : 600,
            foregroundFillSeconds: fill,
            catalogEngines: catalogEngines(mlxListed: mlxListed),
            sceneIsBackground: sceneIsBackground
        )
        #else
        log.notice("Kokoro engine not linked in this build")
        // `T2S_WARMUP=1` (screenshots): the everyday build has no warm-up, so this stands in for
        // one — `preparing` for the launch, with a remembered 12 s and stages ticking by.
        let status = KokoroStatusModel(.notLinked)
        if let fake = ProcessInfo.processInfo.environment["T2S_WARMUP"] {
            status.recordWarmUp(seconds: 12)
            status.update(.preparing)
            Task { @MainActor in
                for loaded in 1...8 {
                    try? await Task.sleep(for: .seconds(1.5))
                    status.updateWarmUp(loaded: loaded, total: 8)
                }
                // `T2S_WARMUP=1` leaves the glow warming for as long as the screenshot needs;
                // `ready` runs the green beat through once, `green` stops on it and holds.
                if fake != "1" { status.update(.available(isDebugOverride: true)) }
            }
        }
        return KokoroComposition(engines: [], voiceRouting: KokoroVoiceRouting.unavailable,
                                 status: status, playAheadWindowSeconds: nil, foregroundFillSeconds: nil, catalogEngines: { [] },
                                 sceneIsBackground: OSAllocatedUnfairLock(initialState: true))
        #endif
    }

    #if KOKORO_ENGINE
    /// The Core ML voices always; the MLX voices only where they can actually render.
    ///
    /// Listing 28 voices twice on a phone that can only speak one of the two sets would be a picker
    /// full of choices that silently fall back (spec §6), so the MLX rows are gated on the MLX
    /// verdict. That verdict is not in yet when the composition root builds the catalog — the probe
    /// hashes 340 MB on a detached task — which is why this is a closure the catalog asks on every
    /// draw rather than a list decided once. The voice list observes `KokoroStatusModel.mlxLine`,
    /// which the same probe task writes, so the redraw that adds the rows happens on its own.
    private static func catalogEngines(
        mlxListed: OSAllocatedUnfairLock<Bool>
    ) -> @Sendable () -> [(identity: String, label: String)] {
        {
            var engines: [(identity: String, label: String)] = [(KokoroCoreMLEngine.identity, "")]
            if mlxListed.withLock({ $0 }) { engines.append((KokoroEngine.identity, "MLX")) }
            return engines
        }
    }

    /// The model download and compile (`KokoroCoreMLInstall`), then the warm-up. Runs once per
    /// install directory; every step is resumable, so a launch that is backgrounded or killed
    /// mid-way picks up where it stopped on the next. A failure closes the route for this launch
    /// — the next launch tries again — and tells the reader so.
    private static func install(
        into root: URL,
        gate: ForegroundGate,
        availability: KokoroCoreMLAvailabilityModel,
        engine: GatedKokoroCoreMLEngine,
        routeOpen: OSAllocatedUnfairLock<Bool>,
        status: KokoroStatusModel,
        log: Logger,
        markWarmed: @escaping @Sendable () -> Void
    ) async {
        let installer = KokoroCoreMLInstall(root: root, admission: { await gate.waitUntilForeground() })
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let located = try await installer.install { progress in
                let mapped: KokoroInstallProgress
                switch progress {
                case .waitingForNetwork(let total): mapped = .waitingForNetwork(totalBytes: total)
                case .downloading(let bytes, let total): mapped = .downloading(bytes: bytes, totalBytes: total)
                case .retrying(_, let attempt, let after):
                    mapped = .retrying(attempt: attempt, of: KokoroCoreMLInstall.maximumAttempts, after: after, fraction: 0)
                case .compiling(let stage, let total): mapped = .compiling(stage: stage, totalStages: total)
                }
                Task { @MainActor in status.updateInstall(mapped) }
            }
            let elapsed = clock.now - started
            log.notice("Kokoro Core ML model installed in \(Double(elapsed.components.seconds), format: .fixed(precision: 0), privacy: .public) s")
            KokoroCoreMLEngine.timing("kokoro model installed in \(elapsed.components.seconds) s")
            availability.installed(located)
            routeOpen.withLock { $0 = true }
            status.update(.preparing)
            await warmUp(engine, routeOpen: routeOpen, status: status, log: log, markWarmed: markWarmed)
        } catch is CancellationError {
            return
        } catch {
            log.error("Kokoro Core ML install failed: \(String(describing: error), privacy: .public)")
            KokoroCoreMLEngine.timing("kokoro install failed: \(String(describing: error))")
            status.update(.unavailable(installFailed))
        }
    }

    /// The one-time stage load, reported to the reader through the footer and to the log in seconds,
    /// and — if it will not load at all — the thing that closes the route.
    ///
    /// Two attempts, because the two failures look identical from here and only one of them is the
    /// bundle's fault: a first load can lose to a transient condition (memory pressure while the
    /// system kills something else, a cold filesystem) where a second, two seconds later, succeeds.
    /// A second failure is taken as final: the route closes, so a new document falls back for its
    /// whole length instead of failing utterance by utterance. Cancellation is not a failure — the
    /// engine's own load is shared and retryable — so it is never retried and never closes anything.
    ///
    /// "Finished" is readiness: the t128 duration model and the 3 s and 15 s buckets loaded, which
    /// is enough to render anything in pieces of up to 126 ids. The 7 s and 10 s buckets and then
    /// t256 — the plan that is a first launch on the A13 — follow on the engine's own task.
    private static func warmUp(
        _ engine: GatedKokoroCoreMLEngine,
        routeOpen: OSAllocatedUnfairLock<Bool>,
        status: KokoroStatusModel,
        log: Logger,
        markWarmed: @escaping @Sendable () -> Void
    ) async {
        // Wall time that no clock change can move; the A13's first launch spends minutes here.
        let clock = ContinuousClock()
        let started = clock.now
        for attempt in 1...2 {
            do {
                try await engine.preload { loaded, total in
                    Task { @MainActor in status.updateWarmUp(loaded: loaded, total: total) }
                }
                let elapsed = clock.now - started
                let seconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) * 1e-18
                log.notice("Kokoro Core ML warm-up finished in \(seconds, format: .fixed(precision: 1), privacy: .public) s")
                KokoroCoreMLEngine.timing("kokoro warm-up finished in \(KokoroCoreMLEngine.fixed(seconds, 1)) s")
                status.recordWarmUp(seconds: seconds)
                // Never an override: the Core ML decision is measured, not a development escape hatch.
                status.update(.available(isDebugOverride: false))
                // "Warmed" is what a background Prepare launch checks before it renders: on a phone
                // whose main set is on the GPU that means the CPU set behind it, which follows the
                // main load and may take minutes — so the record waits for it, the status does not.
                status.updateBackgroundSet(building: true)
                Task {
                    let canRenderBehind = (try? await engine.awaitBackgroundSet()) ?? false
                    await MainActor.run { status.updateBackgroundSet(building: false) }
                    if canRenderBehind { markWarmed() }
                }
                return
            } catch is CancellationError {
                return
            } catch {
                guard attempt == 1 else {
                    routeOpen.withLock { $0 = false }
                    // The engine's own error, never a request: this string reaches the log only.
                    log.error("Kokoro Core ML warm-up failed, route closed: \(error.localizedDescription, privacy: .public)")
                    KokoroCoreMLEngine.timing("kokoro warm-up failed, route closed: \(String(describing: error))")
                    status.update(.unavailable(warmUpFailed))
                    return
                }
                log.notice("Kokoro Core ML warm-up failed, retrying: \(error.localizedDescription, privacy: .public)")
                KokoroCoreMLEngine.timing("kokoro warm-up failed, retrying: \(String(describing: error))")
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    /// What the footer says when the stages will not load. A reader cannot act on Core ML's own
    /// message — and `localizedDescription` on a plain Swift error is "The operation couldn't be
    /// completed." — so they get one sentence and the log gets the error. No "on this device" here:
    /// `VoiceListPage`'s footer already opens with "Not available on this device: ".
    private static let warmUpFailed = "The Kokoro voice could not be prepared."
    /// What the footer says when the download or the compile failed; the next launch tries again.
    private static let installFailed = "The Kokoro voice could not be downloaded. It will try again the next time the app opens."

    /// `Reason.resources` describes a missing file in a developer's bundle, which is not something
    /// to put in front of a reader. The full reason still goes to the log.
    private static func readerFacing(_ reason: KokoroCoreMLAvailability.Reason) -> String {
        switch reason {
        case .notInstalled: "The Kokoro voice is not downloaded yet."
        case .resources: "The Kokoro voice files are not installed."
        }
    }
    #endif
}
