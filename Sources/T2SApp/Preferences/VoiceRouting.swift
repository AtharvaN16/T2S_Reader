import T2SAudio

/// Resolves the voice a document will actually render with, before any render key is built (spec
/// §5, §6): a route whose engine is unavailable on this device falls back to the system default for
/// the whole document, never mid-utterance. The stored `Document.voiceID` is not changed — the
/// user's choice survives until the engine is available.
public protocol VoiceRouteResolving: Sendable {
    func effectiveVoiceID(_ requested: String) async -> String
}

/// Every route is served as chosen: the default, and what the everyday non-Kokoro build needs.
public struct PassthroughVoiceRouting: VoiceRouteResolving {
    public init() {}

    public func effectiveVoiceID(_ requested: String) async -> String { requested }
}

/// Routes `kokoro:` IDs: they render with Kokoro only when `isAvailable()` is true and the ID's
/// engine identity is this build's; otherwise the whole document falls back to
/// `VoiceOption.systemDefault.id`. Non-Kokoro IDs pass through.
public struct KokoroVoiceRouting: VoiceRouteResolving {
    private let engineIdentity: String?
    private let isAvailable: @Sendable () async -> Bool

    public init(engineIdentity: String?, isAvailable: @escaping @Sendable () async -> Bool) {
        self.engineIdentity = engineIdentity
        self.isAvailable = isAvailable
    }

    /// The everyday build, where Kokoro is not linked at all.
    public static let unavailable = KokoroVoiceRouting(engineIdentity: nil, isAvailable: { false })

    public func effectiveVoiceID(_ requested: String) async -> String {
        guard let kokoroID = KokoroVoiceID(rawValue: requested) else { return requested }
        // Identity first: a foreign engine identity is refused without waking a probe.
        guard kokoroID.engineID == engineIdentity, await isAvailable() else {
            return VoiceOption.systemDefault.id
        }
        return requested
    }
}
