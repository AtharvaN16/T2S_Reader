import Foundation
import T2SAudio

/// One bed the reader can choose (soundscape design §4.2). "Off" is `nil` everywhere, not a case.
public struct Soundscape: Identifiable, Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// A bundled `.m4a` named `soundscape-<id>`, fetched by `scripts/fetch-soundscapes.sh`.
        case recording(resource: String)
        /// Made in code when chosen; nothing in the bundle.
        case noise(NoiseColour)
    }

    public let id: String
    public let title: String
    /// The SF Symbol the pill wears.
    public let glyph: String
    public let source: Source

    /// The catalogue, in the order the pills are drawn.
    public static let all: [Soundscape] = [
        Soundscape(id: "rain", title: "Rain", glyph: "cloud.rain", source: .recording(resource: "soundscape-rain")),
        Soundscape(id: "fire", title: "Fire", glyph: "flame", source: .recording(resource: "soundscape-fire")),
        Soundscape(id: "ocean", title: "Ocean", glyph: "water.waves", source: .recording(resource: "soundscape-ocean")),
        Soundscape(id: "stream", title: "Stream", glyph: "drop", source: .recording(resource: "soundscape-stream")),
        Soundscape(id: "forest", title: "Forest", glyph: "tree", source: .recording(resource: "soundscape-forest")),
        Soundscape(id: "night", title: "Night", glyph: "moon.stars", source: .recording(resource: "soundscape-night")),
        Soundscape(id: "brown", title: "Brown noise", glyph: "waveform", source: .noise(.brown)),
        Soundscape(id: "pink", title: "Pink noise", glyph: "waveform.path", source: .noise(.pink)),
    ]

    /// The bed with this id, or nil for an unknown id — and for nil, which is Off.
    public static func named(_ id: String?) -> Soundscape? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
