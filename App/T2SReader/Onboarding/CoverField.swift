// App/T2SReader/Onboarding/CoverField.swift
import SwiftUI
import T2SApp

/// The welcome's first scene: one field of book covers drifting upward in depth parallax while a
/// few opening lines chatter past, and the hero settling out of the crowd at the end (design:
/// `docs/superpowers/specs/2026-09-14-onboarding-design.md`; the owner's references, the Queue
/// podcast app's field of covers and the ATC replay app's card that settles out of the drift).
/// Depth, not motion sensing, and no tap: the voices start with the field.
///
/// One field, no lanes (the owner, 2026-09-14: "there are no separate planes … the covers are
/// just for show, the audio need not align perfectly"). Every cover has its own distance, which
/// sets its size, its speed, its blur and its dimness together, and they are scattered across the
/// whole width with the edges cutting some off, so the field reads as wider than the phone. The
/// books that speak sit nearer than the rest, so they are large and clear while their lines are
/// up, but they drift where they drift. The placing is seeded from each cover's index, so the
/// field is the same every launch.
///
/// The hero is one cover in the field until `ChatterSchedule.settleStart`; then it leaves its
/// drift for the rest top centre at the size it had, and only once there grows to `heroHeight`
/// while the rest of the field dims out — the ATC app's red card left alone on the ground. When
/// the lines are read (`lift`) it moves up and shrinks to make room for them.
///
/// With Reduce Motion nothing travels: the field stands still and dim, and the hero fades in at
/// its rest.
struct CoverField: View {
    var books: [OnboardingManifest.Book]
    var hero: String
    var schedule: ChatterSchedule
    var elapsed: TimeInterval
    /// 0 with the hero at its rest, 1 with it lifted and small above the lines being read.
    var lift: Double = 0

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let heroHeight: CGFloat = 280
    static let liftedHeight: CGFloat = 150
    /// Where the hero rests, as a fraction of the height above the centre; and where it goes when
    /// lifted for the lines.
    static let heroRest: CGFloat = -0.16
    static let heroLifted: CGFloat = -0.31
    /// The settle is two beats (the owner, 2026-09-14: "settle into position, and then expand in
    /// size, while the background fades, not jump to position"): from `settleStart` the hero
    /// leaves the drift for its rest at the size it had, over `arriveDuration`; then, from
    /// `growDelay` after the start, it grows to `heroHeight` over `growDuration` while the crowd
    /// fades on the same clock.
    static let arriveDuration: TimeInterval = 1.3
    static let growDelay: TimeInterval = 1.1
    static let growDuration: TimeInterval = 1.4

    /// One floating cover: where it is in depth and across the screen, and how fast it drifts.
    /// All derived from the index, once.
    struct Placement {
        var depth: Double      // 0 far … 1 near
        var x: CGFloat         // fraction of the width from the centre; beyond ±0.5 is off the edge
        var phase: CGFloat     // fraction of the loop it starts at
        var lean: Double

        var height: CGFloat { 76 + CGFloat(depth) * 150 }
        /// Points per second, upward. A narrow spread: a wide one pulled neighbours together
        /// within seconds and left clumps and gaps (the owner, 2026-09-14: "the spacing is random").
        var speed: CGFloat { 16 + CGFloat(depth) * 12 }
        /// Strictly by depth, and gentle: the furthest cover is soft, not a smear — you can still
        /// make it out — and anything in the near third is sharp (the owner, 2026-09-14: "the most
        /// furthest cover should also not be super blurred … reduce the blur intensity across the
        /// board"; 2026-09-15: "the least blurred book is still very blurred").
        var blur: CGFloat { depth >= 0.66 ? 0 : 3.5 * CGFloat(1 - depth / 0.66) }
        var opacity: Double { 0.5 + depth * 0.5 }

        /// The columns the covers take in turn along the loop, as fractions of the width from the
        /// centre: each is on the other side from the one before, and a column repeats only every
        /// few covers, so neighbours along the loop never stack.
        static let columns: [CGFloat] = [-0.34, 0.34, 0.02, -0.26, 0.30, -0.08, 0.36, -0.36, 0.12, -0.20, 0.24, -0.32]

        /// The first integer at or above two fifths of `count` that shares no factor with it, so
        /// `index * stride % count` visits every slot once.
        static func stride(for count: Int) -> Int {
            guard count > 2 else { return 1 }
            func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
            var s = max(Int(Double(count) * 0.4), 1)
            while gcd(s, count) != 1 { s += 1 }
            return s
        }

        /// Placed by slot, not by chance: cover `index` of `count` takes an even share of the loop
        /// and the next column in turn, with a little jitter on each, so the field is spaced at
        /// the start and stays spaced. Depth and lean are hashed from the index, so the field is
        /// the same every launch. A book that speaks is kept to the near half of the depth.
        init(index: Int, count: Int, near: Bool) {
            func unit(_ salt: UInt32) -> Double {
                var h = UInt32(truncatingIfNeeded: index) &* 2_654_435_761 &+ salt &* 40_503
                h ^= h >> 13; h = h &* 1_274_126_177; h ^= h >> 16
                return Double(h % 10_007) / 10_007
            }
            depth = near ? 0.62 + unit(1) * 0.38 : unit(1)
            // The slot is the index times a stride coprime with the count, so books that sit
            // together in the manifest — the voiced ones do — are spread around the loop rather
            // than arriving as a bunch.
            let slot = (index * Self.stride(for: count)) % max(count, 1)
            x = Self.columns[slot % Self.columns.count] + CGFloat(unit(2) - 0.5) * 0.1
            phase = (CGFloat(slot) + CGFloat(unit(3) - 0.5) * 0.4) / CGFloat(max(count, 1))
            lean = (unit(4) - 0.5) * 24
        }
    }

    private struct Placed {
        var book: OnboardingManifest.Book
        var index: Int
        var placement: Placement
        var isHero: Bool
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Far to near, so a near cover overlaps a far one; the hero last of all, so its
                // settle rides over everything.
                ForEach(Array(placed.enumerated()), id: \.offset) { _, item in
                    card(item, in: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }

    private var placed: [Placed] {
        books.enumerated()
            .map { index, book in
                Placed(book: book,
                       index: index,
                       placement: Placement(index: index, count: books.count, near: book.isVoiced || book.id == hero),
                       isHero: book.id == hero)
            }
            .sorted { a, b in
                if a.isHero != b.isHero { return b.isHero }
                return a.placement.depth < b.placement.depth
            }
    }

    /// 0 before the hero begins to settle, 1 once it is at rest.
    private var arrive: Double {
        smooth((elapsed - schedule.settleStart) / Self.arriveDuration)
    }

    /// 0 until the hero has all but arrived, 1 once it is full size and the crowd is gone.
    private var grow: Double {
        smooth((elapsed - schedule.settleStart - Self.growDelay) / Self.growDuration)
    }

    /// A cover's drift position at `time`: `phase` of the way up its loop at the start, upward
    /// at its speed, wrapping to below the screen past the top.
    private func driftY(_ placement: Placement, at time: TimeInterval, in size: CGSize) -> CGFloat {
        let loop = Self.loop(in: size)
        let travelled = reduceMotion ? 0 : placement.speed * time
        let along = (placement.phase * loop + travelled).truncatingRemainder(dividingBy: loop)
        return loop / 2 - along
    }

    /// The loop is well over two screens tall and the same for every cover, so at any moment under
    /// half the field is on screen with white space between (the owner, 2026-09-14: "too crowded,
    /// not enough white space"; Queue shows about a dozen at once), and a slot along it is the
    /// same distance for a small cover as for a large one.
    private static func loop(in size: CGSize) -> CGFloat {
        size.height * 2.3 + 240
    }

    /// The hero's own placing: near, centred, upright, and timed so that as the settle begins it
    /// is in the lower half of the screen — it has come up from the bottom with the others over
    /// the seconds before, one of the moving books, and then leaves the drift straight up the
    /// middle to its rest (the owner, 2026-09-14: "Alice should not come from the side", "should
    /// be part of the books moving up, should not arrive from nowhere").
    private func heroPlacement(index: Int, in size: CGSize) -> Placement {
        var p = Placement(index: index, count: books.count, near: true)
        p.depth = 0.95
        p.x = 0
        p.lean = 0
        let loop = Self.loop(in: size)
        let alongAtSettle = loop / 2 - size.height * 0.22   // a fifth of the way down from the centre
        let phase = (alongAtSettle - p.speed * schedule.settleStart) / loop
        p.phase = phase - floor(phase)
        return p
    }

    @ViewBuilder
    private func card(_ item: Placed, in size: CGSize) -> some View {
        if item.isHero {
            // In the drift until the settle begins — timed to be in the lower half of the screen
            // then — eased up the centre to its rest, grown once there, and lifted for the lines.
            let p = heroPlacement(index: item.index, in: size)
            let a = arrive
            let g = grow
            let drifting = driftY(p, at: min(elapsed, schedule.settleStart), in: size)
            let rest = size.height * (Self.heroRest + (Self.heroLifted - Self.heroRest) * lift)
            let y = drifting + (rest - drifting) * a
            let full = Self.heroHeight + (Self.liftedHeight - Self.heroHeight) * lift
            let height = p.height + (full - p.height) * g
            BookCover(relativePath: nil, paths: env.paths, height: height,
                      title: item.book.title, author: item.book.author, asset: item.book.coverName)
                .blur(radius: p.blur * (1 - a))
                .offset(y: reduceMotion ? rest : y)
                .opacity(reduceMotion ? a : p.opacity + (1 - p.opacity) * a)
        } else {
            let p = item.placement
            BookCover(relativePath: nil, paths: env.paths, height: p.height,
                      title: item.book.title, author: item.book.author, asset: item.book.coverName)
                .rotationEffect(.degrees(p.lean))
                .blur(radius: p.blur)
                .offset(x: size.width * p.x, y: driftY(p, at: elapsed, in: size))
                .opacity(p.opacity * (reduceMotion ? 0.6 : 1) * (1 - grow))
        }
    }

    private func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
