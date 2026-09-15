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
/// sets its size, its speed, its blur and its dimness together; they are scattered across the
/// whole width with the edges cutting some off, so the field reads as wider than the phone; a few
/// small ones are sharp, as a camera would have it. The books that speak sit nearer than the
/// rest, so they are large and clear while their lines are up, but they drift where they drift.
/// The placing is seeded from each cover's index, so the field is the same every launch.
///
/// The hero is one cover in the field until `RisingChoreography.settleStart`; then it leaves its
/// drift for the rest top centre, sharpening and growing to `heroHeight` on the way, while the
/// rest of the field dims out — the ATC app's red card left alone on the ground.
///
/// With Reduce Motion nothing travels: the field stands still and dim, and the hero fades in at
/// its rest.
struct CoverField: View {
    var books: [OnboardingManifest.Book]
    var hero: String
    var scene: RisingChoreography
    var elapsed: TimeInterval

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let heroHeight: CGFloat = 280
    /// Where the hero rests, as a fraction of the height above the centre.
    static let heroRest: CGFloat = -0.16
    /// How long the hero takes to reach its rest, and the field to dim, from `settleStart`.
    static let settleDuration: TimeInterval = 1.4

    /// One floating cover: where it is in depth and across the screen, how fast it drifts, and
    /// whether it is one of the sharp few. All derived from the index, once.
    struct Placement {
        var depth: Double      // 0 far … 1 near
        var x: CGFloat         // fraction of the width from the centre; beyond ±0.5 is off the edge
        var phase: CGFloat     // fraction of the loop it starts at
        var lean: Double
        var isSharp: Bool

        var height: CGFloat { 84 + CGFloat(depth) * 176 }
        var speed: CGFloat { 9 + CGFloat(depth) * 38 }          // points per second, upward
        var blur: CGFloat { isSharp ? 0 : 15 * CGFloat(pow(1 - depth, 1.3)) }
        var opacity: Double { 0.45 + depth * 0.55 }

        /// A small hash of the index, four ways, so the field is the same every launch. A book
        /// that speaks is kept to the near half of the depth.
        init(index: Int, near: Bool) {
            func unit(_ salt: UInt32) -> Double {
                var h = UInt32(truncatingIfNeeded: index) &* 2_654_435_761 &+ salt &* 40_503
                h ^= h >> 13; h = h &* 1_274_126_177; h ^= h >> 16
                return Double(h % 10_007) / 10_007
            }
            depth = near ? 0.62 + unit(1) * 0.38 : unit(1)
            x = CGFloat(unit(2) - 0.5) * (near ? 0.9 : 1.15)
            phase = CGFloat(unit(3))
            lean = (unit(4) - 0.5) * 24
            isSharp = !near && index % 7 == 3 && depth < 0.55
        }
    }

    private struct Placed {
        var book: OnboardingManifest.Book
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
                       placement: Placement(index: index, near: book.isVoiced || book.id == hero),
                       isHero: book.id == hero)
            }
            .sorted { a, b in
                if a.isHero != b.isHero { return b.isHero }
                return a.placement.depth < b.placement.depth
            }
    }

    /// 0 before the hero begins to settle, 1 once it is at rest.
    private var settle: Double {
        smooth((elapsed - scene.settleStart) / Self.settleDuration)
    }

    /// A cover's drift position at `time`: `phase` of the way up its loop at the start, upward
    /// at its speed, wrapping to below the screen past the top.
    private func driftY(_ placement: Placement, at time: TimeInterval, in size: CGSize) -> CGFloat {
        let loop = size.height + placement.height * 1.6
        let travelled = reduceMotion ? 0 : placement.speed * time
        let along = (placement.phase * loop + travelled).truncatingRemainder(dividingBy: loop)
        return loop / 2 - along
    }

    @ViewBuilder
    private func card(_ item: Placed, in size: CGSize) -> some View {
        let p = item.placement
        if item.isHero {
            // In the drift until the settle begins, then eased from where it was to its rest.
            let s = settle
            let frozen = driftY(p, at: min(elapsed, scene.settleStart), in: size)
            let y = frozen + (size.height * Self.heroRest - frozen) * s
            let x = size.width * p.x * (1 - s)
            let height = p.height + (Self.heroHeight - p.height) * s
            BookCover(relativePath: nil, paths: env.paths, height: height,
                      title: item.book.title, author: item.book.author, asset: item.book.coverName)
                .rotationEffect(.degrees(p.lean * (1 - s)))
                .blur(radius: p.blur * (1 - s))
                .offset(x: x, y: y)
                .opacity(reduceMotion ? s : p.opacity + (1 - p.opacity) * s)
        } else {
            BookCover(relativePath: nil, paths: env.paths, height: p.height,
                      title: item.book.title, author: item.book.author, asset: item.book.coverName)
                .rotationEffect(.degrees(p.lean))
                .blur(radius: p.blur)
                .offset(x: size.width * p.x, y: driftY(p, at: elapsed, in: size))
                .opacity(p.opacity * (reduceMotion ? 0.6 : 1) * (1 - settle))
        }
    }

    private func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
