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
    case compiling(stage: Int, totalStages: Int)

    /// 0…1 for the veil's bar.
    var fraction: Double {
        switch self {
        case .waitingForNetwork: 0
        case .downloading(let bytes, let total): total > 0 ? Double(bytes) / Double(total) : 0
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
    /// The install as it stands, while `status` is `.installing`.
    private(set) var installProgress: KokoroInstallProgress?
    /// Whether a foreground warm-up has built this install's compute plans (`KokoroWarmUpRecord`):
    /// what a background Prepare launch checks before it touches the engine. True in the everyday
    /// build, which has no plans to build.
    private(set) var warmedInstall: Bool

    init(_ status: KokoroStatus, warmedInstall: Bool = true) {
        self.status = status
        self.warmedInstall = warmedInstall
    }

    func update(_ status: KokoroStatus) {
        self.status = status
        if case .preparing = status {
            warmUpStarted = Date()
            warmUpStages = nil
            expectedWarmUpSeconds = Self.storedWarmUpSeconds
        } else {
            warmUpStarted = nil
            warmUpStages = nil
        }
        if case .installing = status {} else { installProgress = nil }
    }

    func updateWarmUp(loaded: Int, total: Int) {
        warmUpStages = (loaded, total)
    }

    func updateInstall(_ progress: KokoroInstallProgress) {
        installProgress = progress
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
    /// The runtimes whose voices the picker lists, with the qualifier each row carries — asked every
    /// time the list is drawn, because the MLX probe answers seconds after the composition root has
    /// finished. Returns an empty list in the everyday build.
    private let catalogEngines: @Sendable () -> [(identity: String, label: String)]

    /// The user default that picks the compute units for the session (`KokoroComputeUnits`
    /// raw values: `cpu`, `cpuAndNeuralEngine`, `cpuAndGPU`, `all`); unset is `cpu`, the measured
    /// policy. A developer's switch for the audit's §3.7 measurement, not a setting.
    static let computeUnitsKey = "kokoro.computeUnits"

    /// Adds the bundled Kokoro voices to the picker, in the build that has the engine.
    func catalog(wrapping base: any VoiceCatalog) -> any VoiceCatalog {
        // Whether Kokoro is linked at all is fixed at compile time; only which runtimes are listed
        // changes as the probes answer, and that is the catalog's own question from here on.
        guard !catalogEngines().isEmpty else { return base }
        return KokoroVoiceCatalog(base: base, engines: catalogEngines)
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
        let computeUnits = defaults.string(forKey: computeUnitsKey).flatMap(KokoroComputeUnits.init(rawValue:)) ?? .cpu
        if computeUnits != .cpu {
            log.notice("Kokoro compute units overridden for this session: \(computeUnits.runtimeName, privacy: .public)")
        }
        let coreMLEngine = GatedKokoroCoreMLEngine(availability: coreML, computeUnits: computeUnits,
                                                   admission: { await gate.waitUntilForeground() })
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
            log.notice("Kokoro Core ML route available (\(decision.runtime, privacy: .public), RTF \(decision.measuredRTF, format: .fixed(precision: 3), privacy: .public))")
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
            catalogEngines: catalogEngines(mlxListed: mlxListed)
        )
        #else
        log.notice("Kokoro engine not linked in this build")
        // `T2S_WARMUP=1` (screenshots): the everyday build has no warm-up, so this stands in for
        // one — `preparing` for the launch, with a remembered 12 s and stages ticking by.
        let status = KokoroStatusModel(.notLinked)
        if ProcessInfo.processInfo.environment["T2S_WARMUP"] != nil {
            status.recordWarmUp(seconds: 12)
            status.update(.preparing)
            Task { @MainActor in
                for loaded in 1...8 {
                    try? await Task.sleep(for: .seconds(1.5))
                    status.updateWarmUp(loaded: loaded, total: 8)
                }
            }
        }
        return KokoroComposition(engines: [], voiceRouting: KokoroVoiceRouting.unavailable,
                                 status: status, catalogEngines: { [] })
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
                case .compiling(let stage, let total): mapped = .compiling(stage: stage, totalStages: total)
                }
                Task { @MainActor in status.updateInstall(mapped) }
            }
            let elapsed = clock.now - started
            log.notice("Kokoro Core ML model installed in \(Double(elapsed.components.seconds), format: .fixed(precision: 0), privacy: .public) s")
            availability.installed(located)
            routeOpen.withLock { $0 = true }
            status.update(.preparing)
            await warmUp(engine, routeOpen: routeOpen, status: status, log: log, markWarmed: markWarmed)
        } catch is CancellationError {
            return
        } catch {
            log.error("Kokoro Core ML install failed: \(String(describing: error), privacy: .public)")
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
    /// "Finished" is readiness: the duration models and the 3 s and 15 s buckets loaded, which is
    /// enough to render anything. The 7 s and 10 s buckets follow on the engine's own task.
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
                status.recordWarmUp(seconds: seconds)
                // Never an override: the Core ML decision is measured, not a development escape hatch.
                status.update(.available(isDebugOverride: false))
                markWarmed()
                return
            } catch is CancellationError {
                return
            } catch {
                guard attempt == 1 else {
                    routeOpen.withLock { $0 = false }
                    // The engine's own error, never a request: this string reaches the log only.
                    log.error("Kokoro Core ML warm-up failed, route closed: \(error.localizedDescription, privacy: .public)")
                    status.update(.unavailable(warmUpFailed))
                    return
                }
                log.notice("Kokoro Core ML warm-up failed, retrying: \(error.localizedDescription, privacy: .public)")
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
