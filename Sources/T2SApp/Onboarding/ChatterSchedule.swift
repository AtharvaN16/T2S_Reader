import Foundation

/// The clock the welcome's chatter runs on: when each voiced line starts, how it fades in, and how
/// the next fades into its tail (design: `docs/superpowers/specs/2026-09-14-onboarding-design.md`;
/// the owner, 2026-09-14: "let each voice finish, and fade the next voice into it").
///
/// Lines play whole, one after another: each rises over `fadeIn`, holds, and falls away over its
/// last `crossfade` seconds while the next line rises under it, so the voices hand over rather
/// than cut. Each has its own base gain, so the chatter has near and far voices. The field is not
/// tied to any of this — the covers drift for show — except that the hero begins to settle as the
/// last line tails off, and the scene ends once it has grown into its rest.
///
/// Pure, so the timing can be tested and the field, the player and the cover agree.
public struct ChatterSchedule: Hashable, Sendable {
    /// The voiced clips' lengths, in play order. Empty is allowed: a field with no chatter.
    public var durations: [TimeInterval]
    public var fadeIn: TimeInterval
    public var crossfade: TimeInterval

    public static let defaultFadeIn: TimeInterval = 0.6
    public static let defaultCrossfade: TimeInterval = 1.2
    /// A pause at the start before the first voice, and the field alone when there is none.
    public static let lead: TimeInterval = 1.0
    /// From the settle's start to the scene's end: the hero arriving, then growing.
    public static let settleLength: TimeInterval = 2.8
    /// Near and far voices, cycled over the lines.
    public static let baseGains: [Float] = [0.85, 0.6, 1.0, 0.7]

    public init(durations: [TimeInterval], fadeIn: TimeInterval = defaultFadeIn, crossfade: TimeInterval = defaultCrossfade) {
        self.durations = durations
        self.fadeIn = fadeIn
        self.crossfade = crossfade
    }

    public var count: Int { durations.count }

    /// When line `index` starts: the previous line's end less the crossfade, never less than half
    /// a second after the previous start, so a very short line still gets heard.
    public func start(of index: Int) -> TimeInterval {
        var at = Self.lead
        for i in 0 ..< index {
            at = max(at + durations[i] - crossfade, at + 0.5)
        }
        return at
    }

    public func end(of index: Int) -> TimeInterval { start(of: index) + durations[index] }

    /// When the hero begins to settle: as the last line tails off, or after the lead alone.
    public var settleStart: TimeInterval {
        guard count > 0 else { return Self.lead + 2 }
        return max(end(of: count - 1) - crossfade * 0.5, start(of: count - 1))
    }

    /// The scene's end: the hero at rest and full size.
    public var total: TimeInterval { settleStart + Self.settleLength }

    /// The line's volume at `time`, 0...1 with its base gain: up over `fadeIn`, held, and down
    /// over its last `crossfade` seconds.
    public func gain(of index: Int, at time: TimeInterval) -> Float {
        let start = start(of: index), end = end(of: index)
        guard time >= start, time < end else { return 0 }
        let rise = Float(min((time - start) / fadeIn, 1))
        let fall = Float(min((end - time) / crossfade, 1))
        return min(rise, fall) * Self.baseGains[index % Self.baseGains.count]
    }

    public func gains(at time: TimeInterval) -> [Float] {
        (0 ..< count).map { gain(of: $0, at: time) }
    }
}
