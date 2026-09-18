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
    /// When the reel gives way and the first veil starts up.
    public var reelEnd: TimeInterval
    /// How long a veil takes to travel the height of the screen. The same for both rises — they
    /// are the one overlay moving twice, not two effects.
    public var rise: TimeInterval
    /// The app's name alone on the ground, between the two rises.
    public var hold: TimeInterval

    /// How long the reel runs before the name covers it.
    ///
    /// It used to be however long the chatter took — a few opening lines read one after another,
    /// about thirty-five seconds of it. Both halves of that are gone on the owner's word
    /// (2026-09-18: "remove the voice from the onboarding video and cut the onboarding video
    /// short"). A silent reel has nothing to wait for, and a welcome that holds a reader for half
    /// a minute before saying anything is a toll, not a scene: long enough to read as a shelf that
    /// is moving, and no longer.
    public static let defaultReel: TimeInterval = 4.5
    public static let defaultRise: TimeInterval = 1.15
    /// Long enough to read three words and let them settle, short enough that a reader who already
    /// knows the app is not kept waiting.
    public static let defaultHold: TimeInterval = 1.9

    public init(reelEnd: TimeInterval = defaultReel, rise: TimeInterval = defaultRise, hold: TimeInterval = defaultHold) {
        self.reelEnd = reelEnd
        self.rise = rise
        self.hold = hold
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

    /// How long after the veil is home the app's own name joins the greeting, and how long it
    /// takes to arrive.
    ///
    /// The stagger cannot come from the veil, and that is the whole reason this exists. The veil
    /// uncovers from the foot upward, and the name sits *below* the greeting — so a name carried
    /// up by the veil is revealed first and the greeting second, which is backwards from what is
    /// being said (the owner, 2026-09-18: "the T2S reveal should be in staggered formation so
    /// welcome to and then T2S fades in"). The greeting rides the veil; the name waits on this.
    public static let defaultNameDelay: TimeInterval = 0.35
    public static let defaultNameFade: TimeInterval = 0.75
    public var nameDelay: TimeInterval = defaultNameDelay
    public var nameFade: TimeInterval = defaultNameFade

    /// 0 before the name has begun to arrive, 1 once it is fully in — and well inside the hold, so
    /// it is read whole before the second veil takes it away.
    public func nameIn(at time: TimeInterval) -> Double {
        Self.ramp((time - welcomeStart - rise - nameDelay) / nameFade)
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
