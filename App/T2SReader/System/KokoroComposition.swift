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
    /// The launch warm-up is loading the stages. Reached before ``available`` on every launch of a
    /// build that has the model files.
    case preparing
    case available(isDebugOverride: Bool)
    case unavailable(String)
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

    init(_ status: KokoroStatus) {
        self.status = status
    }

    func update(_ status: KokoroStatus) {
        self.status = status
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

    /// Adds the bundled Kokoro voices to the picker, in the build that has the engine.
    func catalog(wrapping base: any VoiceCatalog) -> any VoiceCatalog {
        // Whether Kokoro is linked at all is fixed at compile time; only which runtimes are listed
        // changes as the probes answer, and that is the catalog's own question from here on.
        guard !catalogEngines().isEmpty else { return base }
        return KokoroVoiceCatalog(base: base, engines: catalogEngines)
    }

    static func make(defaults: UserDefaults = .standard) -> KokoroComposition {
        let log = Logger(subsystem: "com.t2s.reader", category: "kokoro")
        #if KOKORO_ENGINE
        // Presence-only and synchronous (spec §6): the fetch script verified the digests, so the
        // answer for the Core ML route is already here, before the first view is built.
        let coreML = KokoroCoreMLAvailabilityModel(bundle: .main)
        let coreMLEngine = GatedKokoroCoreMLEngine(availability: coreML)
        // The MLX route costs a 340 MB hash, so one probe per launch, started below and memoized —
        // the route's `isAvailable` joins this same work rather than starting a second.
        let mlx = KokoroAvailabilityModel(probe: .live(defaults: defaults))
        // The probe's answer, where the picker can read it. `VoiceCatalog.voices()` is nonisolated
        // and is called from off the main actor in the root package's tests, so the MLX model's
        // main-actor `state` cannot be the source — a lock can.
        let mlxListed = OSAllocatedUnfairLock(initialState: false)
        let status = KokoroStatusModel(.checking)

        // Whether the resolver may still route a document to Core ML. It starts as the presence
        // verdict — the files are there — and the warm-up may close it: a bundle whose stages will
        // never load must route documents *away* from Kokoro (spec §6, whole document) rather than
        // give a reader a book of 200 ms silences. Nothing reopens it before the next launch.
        let coreMLRouteOpen = OSAllocatedUnfairLock(initialState: false)

        switch coreML.verdict {
        case .available(let decision, _):
            coreMLRouteOpen.withLock { $0 = true }
            log.notice("Kokoro Core ML route available (\(decision.runtime, privacy: .public), RTF \(decision.measuredRTF, format: .fixed(precision: 3), privacy: .public))")
            // Loading eight stages takes seconds on a modern phone and minutes on an A13. Pay them
            // now, while the reader is still choosing a book, rather than at the first utterance.
            status.update(.preparing)
            Task { await warmUp(coreMLEngine, routeOpen: coreMLRouteOpen, status: status, log: log) }
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
        return KokoroComposition(engines: [], voiceRouting: KokoroVoiceRouting.unavailable,
                                 status: KokoroStatusModel(.notLinked), catalogEngines: { [] })
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

    /// The one-time stage load, reported to the reader through the footer and to the log in seconds,
    /// and — if it will not load at all — the thing that closes the route.
    ///
    /// Two attempts, because the two failures look identical from here and only one of them is the
    /// bundle's fault: a first load can lose to a transient condition (memory pressure while the
    /// system kills something else, a cold filesystem) where a second, two seconds later, succeeds.
    /// A second failure is taken as final: the route closes, so a new document falls back for its
    /// whole length instead of failing utterance by utterance. Cancellation is not a failure — the
    /// engine's own load is shared and retryable — so it is never retried and never closes anything.
    private static func warmUp(
        _ engine: GatedKokoroCoreMLEngine,
        routeOpen: OSAllocatedUnfairLock<Bool>,
        status: KokoroStatusModel,
        log: Logger
    ) async {
        // Wall time that no clock change can move; the A13's first launch spends minutes here.
        let clock = ContinuousClock()
        let started = clock.now
        for attempt in 1...2 {
            do {
                try await engine.preload()
                let elapsed = clock.now - started
                let seconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) * 1e-18
                log.notice("Kokoro Core ML warm-up finished in \(seconds, format: .fixed(precision: 1), privacy: .public) s")
                // Never an override: the Core ML decision is measured, not a development escape hatch.
                status.update(.available(isDebugOverride: false))
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

    /// `Reason.resources` describes a missing file and tells a developer to run the fetch script,
    /// which is not something to put in front of a reader. The full reason still goes to the log.
    private static func readerFacing(_ reason: KokoroCoreMLAvailability.Reason) -> String {
        switch reason {
        case .resources: "The Kokoro voice files are not installed."
        }
    }
    #endif
}
