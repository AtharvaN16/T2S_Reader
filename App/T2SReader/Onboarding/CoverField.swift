// App/T2SReader/Onboarding/CoverField.swift
import SwiftUI
import T2SApp

/// The welcome's first scene: a crowd of book covers drifting upward in depth parallax, and the
/// few that speak rising sharp through it (design: `docs/superpowers/specs/2026-09-14-onboarding-design.md`;
/// the owner's references, the Queue podcast app's field of covers and the ATC replay app's card
/// that settles out of the drift). Depth, not motion sensing, and no tap: the voices start with
/// the cards.
///
/// The crowd is continuous depth, the way Queue's is (the owner, 2026-09-14: "all books have
/// different positions, parallax, sizes, there is no one blur plane and one visible plane"): every
/// cover has its own distance, which sets its size, its speed, its blur and its dimness together,
/// and they are scattered across the whole width with the edges cutting some off, so the field
/// reads as wider than the phone. A few small ones are sharp, as a camera would have it. The
/// placing is seeded from each cover's index, so the field is the same every launch.
///
/// The rising cards run on `RisingChoreography` through `elapsed`: each crosses the screen at the
/// near, sharp layer while its voice is up. The last is the hero. It rises the same way but eases
/// to rest top centre instead of leaving, and the crowd dims out behind it, the way the ATC app's
/// red card is left alone on the ground.
///
/// With Reduce Motion nothing travels: each rising book fades in and out at the centre for its
/// slot, the crowd stands still and dim, and the hero fades in at its rest.
struct CoverField: View {
    /// The books that rise, the hero last.
    var rising: [OnboardingManifest.Book]
    /// The books that only float.
    var crowd: [OnboardingManifest.Book]
    var scene: RisingChoreography
    var elapsed: TimeInterval

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let nearHeight: CGFloat = 280
    /// Where the hero rests, as a fraction of the height above the centre.
    static let heroRest: CGFloat = -0.16
    /// How long the crowd takes to dim once the hero begins to settle.
    static let crowdFade: TimeInterval = 1.1

    /// The near layer's small variations per card, so a run of them does not read as one card
    /// repeated: a lean and a shift, alternating.
    private static let leans: [Double] = [-4, 3.5, -2.5, 4, -3, 2, 0]
    private static let shifts: [CGFloat] = [-22, 18, -12, 24, -16, 10, 0]

    /// One floating cover: where it is in depth and across the screen, how fast it drifts, and
    /// whether it is one of the sharp few. All derived from the index, once.
    private struct Placement {
        var depth: Double      // 0 far … 1 near
        var x: CGFloat         // fraction of the width from the centre; beyond ±0.5 is off the edge
        var phase: CGFloat     // fraction of the loop it starts at
        var lean: Double
        var isSharp: Bool

        var height: CGFloat { 84 + CGFloat(depth) * 156 }
        var speed: CGFloat { 9 + CGFloat(depth) * 36 }          // points per second, upward
        var blur: CGFloat { isSharp ? 0 : 15 * CGFloat(pow(1 - depth, 1.3)) }
        var opacity: Double { 0.45 + depth * 0.55 }

        /// A small hash of the index, three ways, so the field is the same every launch.
        init(index: Int) {
            func unit(_ salt: UInt32) -> Double {
                var h = UInt32(truncatingIfNeeded: index) &* 2_654_435_761 &+ salt &* 40_503
                h ^= h >> 13; h = h &* 1_274_126_177; h ^= h >> 16
                return Double(h % 10_007) / 10_007
            }
            depth = unit(1)
            x = CGFloat(unit(2) - 0.5) * 1.15
            phase = CGFloat(unit(3))
            lean = (unit(4) - 0.5) * 24
            isSharp = index % 7 == 3 && depth < 0.55
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Far to near, so a near cover overlaps a far one.
                ForEach(Array(placedCrowd.enumerated()), id: \.offset) { _, placed in
                    crowdCard(placed.book, at: placed.placement, in: size)
                }
                ForEach(Array(rising.enumerated()), id: \.offset) { index, book in
                    nearCard(book, index: index, in: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }

    private var placedCrowd: [(book: OnboardingManifest.Book, placement: Placement)] {
        crowd.enumerated()
            .map { (book: $0.element, placement: Placement(index: $0.offset)) }
            .sorted { $0.placement.depth < $1.placement.depth }
    }

    // MARK: The rising cards

    private var crowdOpacity: Double {
        let t = (elapsed - scene.settleStart) / Self.crowdFade
        return 1 - min(max(t, 0), 1)
    }

    @ViewBuilder
    private func nearCard(_ book: OnboardingManifest.Book, index: Int, in size: CGSize) -> some View {
        let isHero = index == scene.heroIndex
        let p = scene.progress(of: index, at: elapsed)
        let travel = Self.nearHeight + size.height   // from fully below to fully above
        let cover = BookCover(relativePath: nil, paths: env.paths, height: Self.nearHeight,
                              title: book.title, author: book.author, asset: book.coverName)

        if reduceMotion {
            // In place, fading: on for its slot, the hero on for good at its rest.
            let fadeIn = smooth(p / 0.15)
            let fadeOut = isHero ? 0 : smooth((p - 0.75) / 0.2)
            cover
                .offset(y: isHero ? size.height * Self.heroRest : 0)
                .opacity(fadeIn * (1 - fadeOut))
        } else if isHero {
            // Up like the others, then eased to rest over the same span, and held.
            let clamped = min(max(p, 0), 1)
            let eased = 1 - pow(1 - clamped, 3)
            let y = (travel / 2) - (travel / 2 - size.height * Self.heroRest) * eased
            let lean = Self.leans[index % Self.leans.count] * (1 - eased)
            cover
                .rotationEffect(.degrees(lean))
                .offset(x: Self.shifts[index % Self.shifts.count] * (1 - eased), y: y)
                .opacity(p >= 0 ? 1 : 0)
        } else {
            // A straight drift from below the screen to above it.
            let y = travel / 2 - travel * p
            cover
                .rotationEffect(.degrees(Self.leans[index % Self.leans.count]))
                .offset(x: Self.shifts[index % Self.shifts.count], y: y)
                .opacity(p > -0.02 && p < 1.02 ? 1 : 0)
        }
    }

    // MARK: The crowd

    @ViewBuilder
    private func crowdCard(_ book: OnboardingManifest.Book, at placement: Placement, in size: CGSize) -> some View {
        let loop = size.height + placement.height * 1.6
        let travelled = reduceMotion ? 0 : placement.speed * elapsed
        // Start `phase` of the way up the loop and drift upward; wrap to below when past the top.
        let along = (placement.phase * loop + travelled).truncatingRemainder(dividingBy: loop)
        let y = loop / 2 - along
        BookCover(relativePath: nil, paths: env.paths, height: placement.height,
                  title: book.title, author: book.author, asset: book.coverName)
            .rotationEffect(.degrees(placement.lean))
            .blur(radius: placement.blur)
            .offset(x: size.width * placement.x, y: y)
            .opacity(placement.opacity * (reduceMotion ? 0.6 : 1) * crowdOpacity)
    }

    private func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
