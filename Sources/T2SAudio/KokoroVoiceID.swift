import Foundation

/// Stable on-device Kokoro voice route, carried in `SynthesisRequest.voiceID` so the existing
/// `RenderKey` structurally invalidates audio when the weights, the runtime or the G2P change.
///
/// Lives in `T2SAudio` rather than beside the engine on purpose: routing, the voice catalog and
/// Preferences all need to read and write these identities, and none of them may link MLX.
/// It mirrors `CloudVoiceID`, whose `cloud:<fingerprint>:<voice>` shape it deliberately echoes.
public struct KokoroVoiceID: Hashable, Sendable {
    public static let prefix = "kokoro:"

    /// The engine identity, e.g. `kokoro-4e9ecdf0-mlx-misaki1.0.6` (checksum, runtime, G2P).
    public let engineID: String
    /// A voice name from `voices.npz`, e.g. `af_heart`.
    public let voice: String
    public let rawValue: String

    public init(engineID: String, voice: String) {
        self.engineID = engineID
        self.voice = voice
        rawValue = "\(Self.prefix)\(engineID):\(voice)"
    }

    /// Exactly one `:` after the prefix, splitting a non-empty engine ID from a non-blank voice.
    /// A third component would make the split ambiguous, so `kokoro:a:b:c` is rejected rather than
    /// silently routed to a voice named `b:c`.
    public init?(rawValue: String) {
        guard rawValue.hasPrefix(Self.prefix) else { return nil }
        let components = rawValue.dropFirst(Self.prefix.count).split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2 else { return nil }
        let engineID = String(components[0])
        let voice = String(components[1])
        guard !engineID.isEmpty, !voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.engineID = engineID
        self.voice = voice
        self.rawValue = rawValue
    }
}

/// A `kokoro:` voice ID reached the router on a build or device that cannot serve it. The existing
/// render policy surfaces the failed utterance and fills it with 200 ms of silence rather than
/// halting the book (spec §6); a document is meant to be routed away from Kokoro before planning.
public enum KokoroRouteError: Error, Equatable, Sendable, LocalizedError {
    case unavailable(engineID: String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Kokoro is not available on this device."
        }
    }
}
