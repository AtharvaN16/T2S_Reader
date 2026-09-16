import Foundation

/// The clock the welcome's three beats run on (design:
/// `docs/superpowers/specs/2026-09-16-onboarding-reel-welcome-page-design.md`; the owner,
/// 2026-09-16: "a fade overlay move from bottom to the top revealing welcome to T2S … after that
/// the overlay will again shift to show a page with an excerpt").
///
/// One veil rises twice. The first rise covers the reel and uncovers the app's name; the second
/// covers the name and uncovers the page. Between them the name holds alone. Everything the scene
/// draws is a function of `elapsed` through this type, so the field, the veil, the chatter and the
/// player all agree without any of them owning a timer.
///
/// ```
/// 0        reelEnd            reelEnd+rise      +hold           +rise
/// |── reel ──|──── rise one ────|──── hold ────|──── rise two ────|── page …
/// ```
///
/// Pure, so the boundaries can be tested without an audio session or a view.
public struct WelcomeScript: Hashable, Sendable {
    /// When the reel gives way and the first veil starts up: the chatter's last line fully tailed
    /// off, so the name never lands over a voice.
    public var reelEnd: TimeInterval
    /// How long a veil takes to travel the height of the screen. The same for both rises — they
    /// are the one overlay moving twice, not two effects.
    public var rise: TimeInterval
    /// The app's name alone on the ground, between the two rises.
    public var hold: TimeInterval

    public static let defaultRise: TimeInterval = 1.15
    /// Long enough to read three words and let them settle, short enough that a reader who already
    /// knows the app is not kept waiting.
    public static let defaultHold: TimeInterval = 1.9

    public init(reelEnd: TimeInterval, rise: TimeInterval = defaultRise, hold: TimeInterval = defaultHold) {
        self.reelEnd = reelEnd
        self.rise = rise
        self.hold = hold
    }

    public init(chatter: ChatterSchedule, rise: TimeInterval = defaultRise, hold: TimeInterval = defaultHold) {
        self.init(reelEnd: chatter.chatterEnd, rise: rise, hold: hold)
    }

    /// Which of the three the scene is in. The veil's travel belongs to the beat it is uncovering,
    /// so `beat(at:)` changes the moment a rise begins — what is being revealed is what the scene
    /// is about, even while most of the screen still shows the last one.
    public enum Beat: Hashable, Sendable {
        case reel, welcome, page
    }

    public var welcomeStart: TimeInterval { reelEnd }
    public var pageStart: TimeInterval { reelEnd + rise + hold }
    /// When the page is fully uncovered and its passage should begin.
    public var pageSettled: TimeInterval { pageStart + rise }

    public func beat(at time: TimeInterval) -> Beat {
        if time >= pageStart { return .page }
        if time >= welcomeStart { return .welcome }
        return .reel
    }

    /// The first veil's travel, 0 at the foot of the screen and 1 home at the crown.
    public func welcomeSweep(at time: TimeInterval) -> Double {
        Self.ramp((time - welcomeStart) / rise)
    }

    /// The second veil's travel, on the same terms.
    public func pageSweep(at time: TimeInterval) -> Double {
        Self.ramp((time - pageStart) / rise)
    }

    /// Smoothstep, clamped: a veil that starts and stops dead reads as a shutter, and the ease is
    /// what makes it read as a sheet being drawn up.
    static func ramp(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
