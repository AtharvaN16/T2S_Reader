import Foundation

/// The clock the welcome's first scene runs on: when each rising card enters, how long it takes to
/// cross the screen, and how loud its voice is at each moment (design:
/// `docs/superpowers/specs/2026-09-14-onboarding-design.md`; the owner, 2026-09-14: "like a
/// chatter, one after the other bleeding and fading into one another, in different volumes,
/// synced with the position of the book as they rise up, brief and quickly move on").
///
/// Cards enter every `stride` seconds and take `travel` seconds from below the screen to above it,
/// so three or so are up at once. A voice's gain follows its card: silent below the screen, up
/// to full in the first fifth of the climb, held through the middle, and faded out before the top
/// — a line longer than the climb is cut by the fade, never finished. Each card has its own base
/// gain, so the chatter has near and far voices. The last card is the hero: it rises the same
/// way but says nothing — its lines wait for the reader's Play (the owner, 2026-09-14) — and
/// eases to rest instead of leaving; the scene ends a breath after it lands.
///
/// Pure, so the field and the audio cannot drift apart and the timing can be tested.
public struct RisingChoreography: Hashable, Sendable {
    public var count: Int
    public var stride: TimeInterval
    public var travel: TimeInterval

    public static let defaultStride: TimeInterval = 1.7
    public static let defaultTravel: TimeInterval = 5.6
    /// Near and far voices, cycled over the cards.
    public static let baseGains: [Float] = [0.85, 0.6, 1.0, 0.7]

    public init(count: Int, stride: TimeInterval = defaultStride, travel: TimeInterval = defaultTravel) {
        self.count = count
        self.stride = stride
        self.travel = travel
    }

    public var heroIndex: Int { max(count - 1, 0) }

    public func start(of index: Int) -> TimeInterval { TimeInterval(index) * stride }

    /// Unclamped: negative before the card enters, 0 as it enters, 1 as it leaves (or, for the
    /// hero, as it comes to rest — the view eases the hero over the same span).
    public func progress(of index: Int, at time: TimeInterval) -> Double {
        (time - start(of: index)) / travel
    }

    /// When the hero begins to settle and the field starts to dim.
    public var settleStart: TimeInterval { start(of: heroIndex) + travel * 0.35 }

    /// When the hero is at rest.
    public var settled: TimeInterval { start(of: heroIndex) + travel }

    /// The scene's end: the hero at rest, with a breath after.
    public var total: TimeInterval { settled + 0.3 }

    /// The voice's volume for its card's position, 0...1, base gain applied. The hero has none.
    public func gain(of index: Int, at time: TimeInterval) -> Float {
        guard index != heroIndex else { return 0 }
        let p = progress(of: index, at: time)
        guard p >= 0, p < 0.92 else { return 0 }
        let rise = Float(min(p / 0.2, 1))
        let fall = p > 0.6 ? Float((0.92 - p) / 0.32) : 1
        return min(rise, fall) * Self.baseGains[index % Self.baseGains.count]
    }

    public func gains(at time: TimeInterval) -> [Float] {
        (0 ..< count).map { gain(of: $0, at: time) }
    }
}
