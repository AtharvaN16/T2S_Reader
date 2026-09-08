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
    /// How far the pitch contour is widened before the decoder (Plan 14, `Delivery`): nil is the
    /// model's own delivery, and 1 is stored as nil, so two IDs that mean the same delivery are equal.
    /// Written after the voice as `@1.25`, so it reaches every render key without touching the stored
    /// voice choice, which never carries it.
    public let spread: Float?
    public let rawValue: String

    public init(engineID: String, voice: String, spread: Float? = nil) {
        self.engineID = engineID
        self.voice = voice
        let normalized = spread.flatMap { $0 == 1 ? nil : $0 }
        self.spread = normalized
        rawValue = "\(Self.prefix)\(engineID):\(voice)" + (normalized.map { "@" + Self.format($0) } ?? "")
    }

    /// The same route at another delivery; nil or 1 is the model's own.
    public func withSpread(_ spread: Float?) -> KokoroVoiceID {
        KokoroVoiceID(engineID: engineID, voice: voice, spread: spread)
    }

    /// Exactly one `:` after the prefix, splitting a non-empty engine ID from a non-blank voice.
    /// A third component would make the split ambiguous, so `kokoro:a:b:c` is rejected rather than
    /// silently routed to a voice named `b:c`. At most one `@` after the voice, followed by a finite,
    /// positive spread; anything else there is rejected rather than rendered at a delivery nobody
    /// chose. The raw value is rebuilt in canonical form, so `@1` and no `@` compare equal.
    public init?(rawValue: String) {
        guard rawValue.hasPrefix(Self.prefix) else { return nil }
        let components = rawValue.dropFirst(Self.prefix.count).split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2 else { return nil }
        let engineID = String(components[0])
        let voiceAndSpread = components[1].split(separator: "@", omittingEmptySubsequences: false)
        guard voiceAndSpread.count <= 2 else { return nil }
        let voice = String(voiceAndSpread[0])
        guard !engineID.isEmpty, !voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var spread: Float?
        if voiceAndSpread.count == 2 {
            guard let value = Float(voiceAndSpread[1]), value.isFinite, value > 0 else { return nil }
            spread = value
        }
        self.init(engineID: engineID, voice: voice, spread: spread)
    }

    /// `1.25` as "1.25", never "1.2500001": the raw value is a cache key and must not depend on how a
    /// float prints.
    private static func format(_ spread: Float) -> String {
        String(format: "%g", spread)
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
