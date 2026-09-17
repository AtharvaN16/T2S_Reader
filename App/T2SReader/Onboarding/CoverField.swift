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
    /// Only to keep the book whose passage beat three reads in the near half of the field, so it
    /// is one of the sharp ones as it goes by. It gets no other treatment.
    var hero: String
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
                Placed(book: book,
                       index: index,
                       placement: Placement(index: index, count: books.count, near: book.isVoiced || book.id == hero))
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

    /// The loop is well over two screens tall and the same for every cover, so at any moment under
    /// half the field is on screen with white space between (the owner, 2026-09-14: "too crowded,
    /// not enough white space"; Queue shows about a dozen at once), and a slot along it is the
    /// same distance for a small cover as for a large one.
    private static func loop(in size: CGSize) -> CGFloat {
        size.height * 2.3 + 240
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
