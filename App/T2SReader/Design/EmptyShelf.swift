// App/T2SReader/Design/EmptyShelf.swift
import SwiftUI

/// The empty state Home and the Collection share (the owner's reference, 2026-09-10: Klarna's
/// "Nothing saved" — a fan of three objects over a soft pool of colour, a headline, one line, one
/// button). The objects are three real covers, bundled: Alex Aster's *Starside* and Kate Quinn's
/// *The Astral Library*, two of 2026's popular books, behind Madeline Miller's *Circe*. Three
/// authors, one each — the first cut had *Circe* and *The Song of Achilles*, both Miller's, and the
/// owner asked for neither that nor a shelf with nothing new on it (2026-09-10: "don't include 2
/// books from the same author, also include 2026 popular books").
///
/// They are drawn as every book in the app is drawn — `BookCover`, the Figma mockup: hinge, sheen,
/// shadow, the fore-edge rounded and the spine square — and each is turned in 3D on its `tilt`, the
/// way the book sheet's hero turns with the phone, so the fan reads as three objects standing at
/// angles rather than three pictures laid flat (the owner, on the first cut: "use our book mockup
/// for the covers"). They rise into place one after another when the page appears, and the one in
/// front keeps a slow breath after. The pool under them is `glowFaint`, the same blue as the
/// warm-up's light and the button below.
struct EmptyShelf: View {
    var title: String
    var line: String
    var button: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CoverFan()
            Text(title).typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                .padding(.top, Spacing.row)
            Text(line).typeRole(.rowTitle).foregroundStyle(Tokens.ink2)
                .padding(.top, 8)
                .padding(.horizontal, Spacing.grid)
            RaisedButton(label: button, glyph: "plus", action: action)
                .padding(.top, Spacing.row)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// The three books: two behind, tilted out like the reference's two shapes, the hero in front and
/// upright. They stand 82 pt out from the middle — at 70 the hero cut both their titles in half. Each starts low, small and clear, and springs up to its place; the two behind land
/// first, the hero last. With Reduce Motion on, nothing moves — the three only fade in together.
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

    private static let books = [
        Book(asset: "EmptyCoverStarside", title: "Starside", angle: -13, x: -82, y: 16, height: 136,
             delay: 0, tilt: CGPoint(x: 9, y: -3)),
        Book(asset: "EmptyCoverAstralLibrary", title: "The Astral Library", angle: 13, x: 82, y: 16, height: 136,
             delay: 0.15, tilt: CGPoint(x: -9, y: -3)),
        Book(asset: "EmptyCoverCirce", title: "Circe", angle: 0, x: 0, y: 0, height: 158,
             delay: 0.32, tilt: CGPoint(x: 0, y: -4)),
    ]
    private static let hero = 2

    var body: some View {
        ZStack {
            // A circle of light squashed to a pool, fully faded before its own edge, so nothing
            // about its frame shows — a hard-cut rectangle did, faintly, at the first look.
            Circle()
                .fill(RadialGradient(stops: [
                    .init(color: Tokens.glowSoft, location: 0),
                    .init(color: Tokens.glowFaint, location: 0.45),
                    .init(color: Tokens.glowFaint.opacity(0), location: 1),
                ], center: .center, startRadius: 0, endRadius: 170))
                .frame(width: 340, height: 340)
                .scaleEffect(x: 1, y: 0.68)
                .offset(y: 12)
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
        .frame(height: 230)
        .onAppear { settled = true }
        .task {
            // The breath starts once the hero has landed; it is never part of the entrance.
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(1.3))
            breathing = true
        }
        .accessibilityHidden(true)
    }
}
