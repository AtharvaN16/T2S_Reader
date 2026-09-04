// App/T2SReader/System/KokoroComposition.swift
#if KOKORO_ENGINE
import T2SKokoro
#endif
import Foundation
import Observation
import OSLog
import T2SApp
import T2SAudio
import T2SCore

/// What Preferences shows for the Kokoro section.
enum KokoroStatus: Hashable, Sendable {
    /// The everyday build, which does not link the engine at all.
    case notLinked
    case checking
    case available(isDebugOverride: Bool)
    case unavailable(String)
}

@MainActor
@Observable
final class KokoroStatusModel {
    private(set) var status: KokoroStatus

    init(_ status: KokoroStatus) {
        self.status = status
    }

    func update(_ status: KokoroStatus) {
        self.status = status
    }
}

/// Everything the composition root needs from the Kokoro package, decided once per launch (spec
/// §3, plan adjustment 3). This is the app's only `#if KOKORO_ENGINE` apart from the gated engine
/// beside it: the route, the fallback resolver and the catalog are all pure types in the root
/// package, so every other file compiles the same way in both builds.
@MainActor
struct KokoroComposition {
    /// The gated engine, or nil in the everyday build — `RoutedEngine` takes it as an option.
    let engine: (any SynthesisEngine)?
    /// How `PlayerModel` and `PrepareRunner` decide a document's effective voice.
    let voiceRouting: any VoiceRouteResolving
    let status: KokoroStatusModel
    /// nil when the engine is not linked, which is also what keeps its voices out of the picker.
    private let engineIdentity: String?

    /// Adds the bundled Kokoro voices to the picker, in the build that has the engine.
    func catalog(wrapping base: any VoiceCatalog) -> any VoiceCatalog {
        guard let engineIdentity else { return base }
        return KokoroVoiceCatalog(base: base, engineIdentity: engineIdentity)
    }

    static func make(defaults: UserDefaults = .standard) -> KokoroComposition {
        let log = Logger(subsystem: "com.t2s.reader", category: "kokoro")
        #if KOKORO_ENGINE
        let availability = KokoroAvailabilityModel(probe: .live(defaults: defaults))
        let status = KokoroStatusModel(.checking)
        // One probe per launch, started now so the answer is usually there before the first play.
        // `resolve()` is memoized, so the route's `isAvailable` below joins this same work.
        Task {
            switch await availability.resolve() {
            case .available(let decision, _):
                log.notice("Kokoro route available (development override: \(decision.isDebugOverride, privacy: .public))")
                status.update(.available(isDebugOverride: decision.isDebugOverride))
            case .unavailable(let reason):
                log.notice("Kokoro unavailable: \(reason.description, privacy: .public)")
                status.update(.unavailable(readerFacing(reason)))
            }
        }
        return KokoroComposition(
            engine: GatedKokoroEngine(availability: availability),
            voiceRouting: KokoroVoiceRouting(engineIdentity: KokoroEngine.identity) {
                if case .available = await availability.resolve() { return true }
                return false
            },
            status: status,
            engineIdentity: KokoroEngine.identity
        )
        #else
        log.notice("Kokoro engine not linked in this build")
        return KokoroComposition(engine: nil, voiceRouting: KokoroVoiceRouting.unavailable,
                                 status: KokoroStatusModel(.notLinked), engineIdentity: nil)
        #endif
    }

    #if KOKORO_ENGINE
    /// `Reason.resources` describes a missing file and tells a developer to run the fetch script,
    /// which is not something to put in front of a reader; every other reason already reads as a
    /// sentence. The full reason still goes to the log.
    private static func readerFacing(_ reason: KokoroAvailability.Reason) -> String {
        if case .resources = reason { return "The Kokoro voice files are not installed." }
        return reason.description
    }
    #endif
}
