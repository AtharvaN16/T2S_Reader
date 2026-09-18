// App/T2SReader/Onboarding/CoverField.swift
import SwiftUI
import T2SApp

/// The welcome's reel: one field of book covers drifting upward in depth parallax, laid back in
/// perspective, while a few opening lines chatter past (design:
/// `docs/superpowers/specs/2026-09-16-onboarding-reel-welcome-page-design.md`; the owner's
/// reference, the Queue podcast app's field of covers). Depth, not motion sensing, and no tap: the
/// voices start with the field.
///
/// One field, no lanes (the owner, 2026-09-14: "there are no separate planes … the covers are
/// just for show, the audio need not align perfectly"). Every cover has its own distance, which
/// sets its size, its speed, its blur and its dimness together, and they are scattered across the
/// whole width with the edges cutting some off, so the field reads as wider than the phone. The
/// books that speak sit nearer than the rest, so they are large and clear while their lines are
/// up, but they drift where they drift. The placing is seeded from each cover's index, so the
/// field is the same every launch.
///
/// **No hero.** A cover used to leave the drift as the last line tailed off, climb to the top,
/// grow, and stand alone while the rest of the field dimmed away — the ATC replay app's red card.
/// The owner asked for that focus to go (2026-09-16: "let us remove the focus on Alice in
/// Wonderland"); the reel now runs unbroken until the welcome's veil covers it, and Alice is one
/// book in it like any other.
///
/// **No skew either, any more.** A cut on 2026-09-16 laid every cover back about its horizontal
/// axis under a perspective divide, so the reel read as a ramp going over a horizon — the owner's
/// Mobbin reference. Seen moving, it was wrong: a record can be laid near-flat because a record is
/// legible flat, and a book laid that far back stops looking like a book. The owner's verdict the
/// next day (2026-09-17: "I don't like that the books are tilted in the start video now, earlier
/// the way we had it, it was fine"). The reel is a flat field again, with nothing but each cover's
/// own small roll to keep it from looking machined.
///
/// With Reduce Motion nothing travels: the field stands still and dim.
struct CoverField: View {
    var books: [OnboardingManifest.Book]
    var elapsed: TimeInterval

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

        /// The turn of the golden angle, in fractions of a circle. Taking this much of the width
        /// per cover and wrapping is a low-discrepancy sequence: consecutive covers land far apart
        /// across the screen, and the set as a whole fills the width evenly without ever settling
        /// into a rhythm. A fixed table of twelve columns did the first of those and not the
        /// second — twelve covers in, the thirteenth stood exactly under the first, and the eye
        /// found the grid (the owner, 2026-09-18: "scatter them more organically").
        static let goldenTurn: Double = 0.618_033_988_75

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
        /// and its own turn across the width, with a little jitter on each, so the field is spaced
        /// at the start and stays spaced. Depth and lean are hashed from the index, so the field is
        /// the same every launch.
        init(index: Int, count: Int) {
            func unit(_ salt: UInt32) -> Double {
                var h = UInt32(truncatingIfNeeded: index) &* 2_654_435_761 &+ salt &* 40_503
                h ^= h >> 13; h = h &* 1_274_126_177; h ^= h >> 16
                return Double(h % 10_007) / 10_007
            }
            depth = unit(1)
            // The slot is the index times a stride coprime with the count, so the covers take even
            // turns along the loop rather than arriving in the manifest's own order.
            let slot = (index * Self.stride(for: count)) % max(count, 1)
            // Across the width by the golden angle, then nudged. The turn does the spreading and
            // the jitter takes the last of the regularity out of it, so no two neighbours share a
            // column and no column is ever exactly repeated.
            let turn = (Double(slot) * Self.goldenTurn).truncatingRemainder(dividingBy: 1)
            x = CGFloat(turn - 0.5) * 0.82 + CGFloat(unit(2) - 0.5) * 0.08
            phase = (CGFloat(slot) + CGFloat(unit(3) - 0.5) * 0.5) / CGFloat(max(count, 1))
            lean = (unit(4) - 0.5) * 24
        }
    }

    private struct Placed {
        var book: OnboardingManifest.Book
        var index: Int
        var placement: Placement
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Far to near, so a near cover overlaps a far one.
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
                Placed(book: book, index: index, placement: Placement(index: index, count: books.count))
            }
            .sorted { $0.placement.depth < $1.placement.depth }
    }

    /// A cover's drift position at `time`: `phase` of the way up its loop at the start, upward
    /// at its speed, wrapping to below the screen past the top.
    private func driftY(_ placement: Placement, at time: TimeInterval, in size: CGSize) -> CGFloat {
        let loop = Self.loop(in: size)
        let travelled = reduceMotion ? 0 : placement.speed * time
        let along = (placement.phase * loop + travelled).truncatingRemainder(dividingBy: loop)
        return loop / 2 - along
    }

    /// The loop is over three screens tall and the same for every cover, so at any moment well
    /// under a third of the field is on screen with room between (the owner, 2026-09-14: "too
    /// crowded, not enough white space", and again 2026-09-18: "enough hidespace between them"),
    /// and a slot along it is the same distance for a small cover as for a large one.
    ///
    /// It was 2.3 screens, which put about ten covers up at once on a 24-book manifest. At 3.4 it
    /// is nearer six, and the reel reads as a few books passing rather than a crowd.
    private static func loop(in size: CGSize) -> CGFloat {
        size.height * 3.4 + 240
    }

    @ViewBuilder
    private func card(_ item: Placed, in size: CGSize) -> some View {
        let p = item.placement
        BookCover(relativePath: nil, paths: env.paths, height: p.height,
                  title: item.book.title, author: item.book.author, asset: item.book.coverName)
            .rotationEffect(.degrees(p.lean))
            .blur(radius: p.blur)
            .offset(x: size.width * p.x, y: driftY(p, at: elapsed, in: size))
            .opacity(p.opacity * (reduceMotion ? 0.6 : 1))
    }
}
