// App/T2SReader/Design/EmptyShelf.swift
import SwiftUI

/// The empty state Home and the Collection share (the owner's reference, 2026-09-10: Klarna's
/// "Nothing saved" — a fan of three objects over a soft pool of colour, a headline, one line). The
/// button that used to sit under the line is gone (owner, 2026-09-14, from Queue's empty pages):
/// the page's own Import control in the top row becomes the raised blue key while the page is
/// empty instead, so there is one way in, not two, and the shelf is only the picture and the words.
///
/// The Collection's objects are three real covers, bundled: Alex Aster's *Starside* and Kate
/// Quinn's *The Astral Library*, two of 2026's popular books, behind Madeline Miller's *Circe*.
/// Three authors, one each — the first cut had *Circe* and *The Song of Achilles*, both Miller's,
/// and the owner asked for neither that nor a shelf with nothing new on it (2026-09-10: "don't
/// include 2 books from the same author, also include 2026 popular books"). They are drawn as
/// every book in the app is drawn — `BookCover`, the Figma mockup: hinge, sheen, shadow, the
/// fore-edge rounded and the spine square — and each is turned in 3D on its `tilt`, the way the
/// book sheet's hero turns with the phone, so the fan reads as three objects standing at angles
/// rather than three pictures laid flat (the owner, on the first cut: "use our book mockup for the
/// covers"). They rise into place one after another when the page appears, and the one in front
/// keeps a slow breath after. The pool under them is `glowFaint`, the same blue as the warm-up's
/// light and the raised key in the page's top row.
///
/// Home's is quieter: grey stand-ins, no covers and no pool (owner, 2026-09-17). Both pictures are
/// smaller than they were, and the headline and its line each dropped a size, so the shelf takes
/// less of an empty page than it did.
struct EmptyShelf: View {
    /// Which picture the page shows. The Collection keeps the fan — three covers standing at
    /// angles over the pool, a shelf with things on it. Home has its own: three grey rows, a square
    /// and two lines each, the queue it will be (owner, 2026-09-14, from the reference's Queue and
    /// Collection pages: "use different graphic for home and collection").
    enum Graphic { case fan, rows }

    var graphic: Graphic
    var title: String
    var line: String

    /// How far below the header's row the picture starts. Home and the Collection lay the shelf
    /// out in different containers (a `List` whose header row ends `Spacing.row` down, a `VStack`
    /// spaced `Spacing.section`), so each subtracts what its container already adds and the
    /// picture lands on the same line on both pages (owner, 2026-09-14: "it is higher in one,
    /// align it"). 128, not a spacing token: it puts the picture's middle a little above the
    /// middle of the screen on a phone (about 380 pt down on 812–874), which is where the owner
    /// asked for it ("slightly lower, just above the center") — at 48 it sat in the top third.
    static let topGap: CGFloat = 128

    /// How tall the picture's frame is on each page. Both were 230 before the owner asked for a
    /// smaller graphic on Home and the Collection to match it (2026-09-17); Home's is the shorter
    /// of the two now, because its rows lost their covers as well as their size.
    private var frameHeight: CGFloat {
        switch graphic {
        case .fan: return 190
        case .rows: return 156
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // One frame per picture, so the headline lands the same distance under either.
            ZStack {
                switch graphic {
                // Home's rows stand on the page itself: the pool of blue behind them went with the
                // covers (owner, 2026-09-17: "remove the blue glow from behind the graphic"). The
                // Collection's fan keeps it — three covers over a pool is the whole picture there.
                case .fan:
                    Pool()
                    CoverFan()
                case .rows:
                    RowStack()
                }
            }
            .frame(height: frameHeight)
            .accessibilityHidden(true)
            Text(title).typeRole(.groupTitle).foregroundStyle(Tokens.ink)
                .padding(.top, Spacing.row)
            Text(line).typeRole(.pill).foregroundStyle(Tokens.ink2)
                .padding(.top, 6)
                .padding(.horizontal, Spacing.grid)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// The three books: two behind, tilted out like the reference's two shapes, the hero in front and
/// upright. They stand 68 pt out from the middle — far enough that the hero does not cut either
/// title in half, which is what 82 bought at the old size. Each starts low, small and clear, and
/// springs up to its place; the two behind land first, the hero last. With Reduce Motion on,
/// nothing moves — the three only fade in together.
private struct CoverFan: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    @State private var breathing = false

    private struct Book {
        var asset: String
        var title: String
        var angle: Double
        var x: CGFloat
        var y: CGFloat
        var height: CGFloat
        var delay: Double
        /// Degrees for `BookCover.tilt`: the two behind turn their outer edges toward the reader,
        /// the one in front stands almost square with its top tipped a little away.
        var tilt: CGPoint
    }

    // Four fifths of the first cut's sizes and spread (136/158 tall, 82 out), so the picture reads
    // the same and takes less of the page — the owner asked Home's graphic to shrink and the
    // Collection's to follow it (2026-09-17).
    private static let books = [
        Book(asset: "EmptyCoverStarside", title: "Starside", angle: -13, x: -68, y: 13, height: 110,
             delay: 0, tilt: CGPoint(x: 9, y: -3)),
        Book(asset: "EmptyCoverAstralLibrary", title: "The Astral Library", angle: 13, x: 68, y: 13, height: 110,
             delay: 0.15, tilt: CGPoint(x: -9, y: -3)),
        Book(asset: "EmptyCoverCirce", title: "Circe", angle: 0, x: 0, y: 0, height: 128,
             delay: 0.32, tilt: CGPoint(x: 0, y: -4)),
    ]
    private static let hero = 2

    var body: some View {
        ZStack {
            ForEach(Array(Self.books.enumerated()), id: \.offset) { index, book in
                let isHero = index == Self.hero
                let moves = !reduceMotion
                BookCover(relativePath: nil, paths: env.paths, height: book.height, title: book.title,
                          tilt: settled || !moves ? book.tilt : .zero, asset: book.asset)
                    .rotationEffect(.degrees(settled || !moves ? book.angle : book.angle * 0.3))
                    .offset(x: settled || !moves ? book.x : book.x * 0.5,
                            y: settled || !moves ? book.y : book.y + 44)
                    .scaleEffect(settled || !moves ? 1 : 0.9)
                    .opacity(settled ? 1 : 0)
                    .animation(moves ? .spring(response: 0.68, dampingFraction: 0.74).delay(book.delay)
                                     : .easeOut(duration: 0.35), value: settled)
                    .offset(y: isHero && breathing ? -5 : 0)
                    .animation(isHero ? .easeInOut(duration: 2.8).repeatForever(autoreverses: true) : nil, value: breathing)
            }
        }
        .onAppear { settled = true }
        .task {
            // The breath starts once the hero has landed; it is never part of the entrance.
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(1.3))
            breathing = true
        }
    }
}

/// The pool of light under the fan: a circle squashed to a pool, fully faded before its
/// own edge, so nothing about its frame shows — a hard-cut rectangle did, faintly, at the first look.
private struct Pool: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: Tokens.glowSoft, location: 0),
                .init(color: Tokens.glowFaint, location: 0.45),
                .init(color: Tokens.glowFaint.opacity(0), location: 1),
            ], center: .center, startRadius: 0, endRadius: 170))
            .frame(width: 280, height: 280)
            .scaleEffect(x: 1, y: 0.68)
            .offset(y: 10)
    }
}

/// Home's picture: three rows of the queue this page will be — a square where a cover will go, a
/// title line and a shorter second line beside it. All of it is `ink3`, the colour of a divider,
/// so the whole row reads as the shape of a row and not as a book the reader missed or words they
/// failed to catch: the three real covers that stood here are gone (owner, 2026-09-17: "use grey
/// rectangles instead of actual book covers"), and with them the argument for the pool of blue
/// behind. The rows slide in from the left one after another when the page appears; with Reduce
/// Motion on they only fade in together.
private struct RowStack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    private struct Row {
        /// The two grey lines' widths: a title and a shorter line under it, no two rows alike, so
        /// the three read as three different books rather than one drawn three times.
        var lines: (CGFloat, CGFloat)
        var delay: Double
    }

    // Four fifths of the first cut's widths, with the cover and the lines to match.
    private static let rows = [
        Row(lines: (78, 48), delay: 0),
        Row(lines: (96, 58), delay: 0.12),
        Row(lines: (64, 42), delay: 0.24),
    ]
    /// A cover's place, not a cover: a square the height of the row, the proportion a stand-in
    /// keeps when it has no book in it.
    private static let coverSide: CGFloat = 40

    var body: some View {
        let moves = !reduceMotion
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Tokens.ink3)
                        .frame(width: Self.coverSide, height: Self.coverSide)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(Tokens.ink3).frame(width: row.lines.0, height: 7)
                        Capsule().fill(Tokens.ink3).frame(width: row.lines.1, height: 7)
                    }
                }
                .offset(x: settled || !moves ? 0 : -28)
                .opacity(settled ? 1 : 0)
                .animation(moves ? .spring(response: 0.6, dampingFraction: 0.8).delay(row.delay)
                                 : .easeOut(duration: 0.35), value: settled)
            }
        }
        .onAppear { settled = true }
    }
}
