import T2SAudio

/// Resolves the voice a document will actually render with, before any render key is built (spec
/// §5, §6): a route whose engine is unavailable on this device falls back to the app's default voice
/// for the whole document, never mid-utterance. The stored `Document.voiceID` is not changed — the
/// user's choice survives until the engine is available.
public protocol VoiceRouteResolving: Sendable {
    func effectiveVoiceID(_ requested: String) async -> String
}

/// Every route is served as chosen: the default, and what the everyday non-Kokoro build needs.
public struct PassthroughVoiceRouting: VoiceRouteResolving {
    public init() {}

    public func effectiveVoiceID(_ requested: String) async -> String { requested }
}

/// Routes `kokoro:` IDs: one route per linked Kokoro runtime, and an ID renders with Kokoro only
/// when its own runtime's route is present and available. Everything else falls back to the app's
/// *default* voice — `defaultVoice` (Kokoro Heart on the Core ML route) where that route is
/// available, and `VoiceOption.systemDefault.id` otherwise — and non-Kokoro IDs pass through.
///
/// Falling back to the default voice rather than straight to the system voice is the whole point of
/// carrying the engine identity inside the voice ID: when a model revision bumps the identity, every
/// document stored against the old one re-routes to the *new* Kokoro default, not to the system
/// voice. The same rule covers a runtime that cannot run here — an MLX voice on a pre-A14 phone
/// speaks with Core ML's Heart.
///
/// It also carries the other direction (spec §6): a reader who has never chosen a voice is given
/// `defaultVoice` — Kokoro Heart on the Core ML route — as long as that route is available.
public struct KokoroVoiceRouting: VoiceRouteResolving {
    /// One linked runtime and the probe that says whether it can run here.
    public struct Route: Sendable {
        public let engineIdentity: String
        public let isAvailable: @Sendable () async -> Bool

        public init(engineIdentity: String, isAvailable: @escaping @Sendable () async -> Bool) {
            self.engineIdentity = engineIdentity
            self.isAvailable = isAvailable
        }
    }

    private let routes: [String: Route]
    /// A full Kokoro voice ID, or nil to leave `"default"` meaning the system voice.
    private let defaultVoice: String?

    public init(routes: [Route], defaultVoice: String?) {
        // First wins, matching `RoutedEngine`: one identity is one runtime.
        self.routes = Dictionary(routes.map { ($0.engineIdentity, $0) }, uniquingKeysWith: { first, _ in first })
        self.defaultVoice = defaultVoice
    }

    /// The single-route form, from before the app linked more than one runtime.
    public init(engineIdentity: String?, isAvailable: @escaping @Sendable () async -> Bool) {
        self.init(routes: engineIdentity.map { [Route(engineIdentity: $0, isAvailable: isAvailable)] } ?? [],
                  defaultVoice: nil)
    }

    /// The everyday build, where Kokoro is not linked at all.
    public static let unavailable = KokoroVoiceRouting(routes: [], defaultVoice: nil)

    public func effectiveVoiceID(_ requested: String) async -> String {
        if let kokoroID = KokoroVoiceID(rawValue: requested) {
            // Identity first: an unrouted engine identity is refused without waking a probe.
            guard await isAvailable(kokoroID.engineID) else {
                // Not the system voice: whatever "default" means on this device, which is the
                // Kokoro default voice wherever its route is open. Exactly one level of recursion —
                // `VoiceOption.systemDefault.id` is not a `kokoro:` ID, so it takes the branch
                // below, which never comes back here.
                return await effectiveVoiceID(VoiceOption.systemDefault.id)
            }
            return requested
        }
        guard requested == VoiceOption.systemDefault.id,
              let defaultVoice,
              let defaultID = KokoroVoiceID(rawValue: defaultVoice),
              await isAvailable(defaultID.engineID)
        else { return requested }
        return defaultVoice
    }

    private func isAvailable(_ engineIdentity: String) async -> Bool {
        guard let route = routes[engineIdentity] else { return false }
        return await route.isAvailable()
    }
}
