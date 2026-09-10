// App/T2SReader/Design/EmptyShelf.swift
import SwiftUI

/// The empty state Home and the Collection share (the owner's reference, 2026-09-10: Klarna's
/// "Nothing saved" — a fan of three objects over a soft pool of colour, a headline, one line, one
/// button). The objects here are three real covers — Circe, The Midnight Library, The Song of
/// Achilles, bundled — drawn as every book in the app is drawn (`BookCover`: hinge, sheen, shadow),
/// fanned like a hand of cards with the gold one in front. They rise into place one after another
/// when the page appears, and the one in front keeps a slow breath after. The pool under them is
/// the accent, faint: the warm glow the app already uses for light.
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
/// upright. Each starts low, small and clear, and springs up to its place; the two behind land
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
    }

    private static let books = [
        Book(asset: "EmptyCoverMidnightLibrary", title: "The Midnight Library", angle: -13, x: -70, y: 16, height: 136, delay: 0),
        Book(asset: "EmptyCoverSongOfAchilles", title: "The Song of Achilles", angle: 13, x: 70, y: 16, height: 136, delay: 0.15),
        Book(asset: "EmptyCoverCirce", title: "Circe", angle: 0, x: 0, y: 0, height: 158, delay: 0.32),
    ]
    private static let hero = 2

    var body: some View {
        ZStack {
            // A circle of light squashed to a pool, fully faded before its own edge, so nothing
            // about its frame shows — a hard-cut rectangle did, faintly, at the first look.
            Circle()
                .fill(RadialGradient(stops: [
                    .init(color: Tokens.accentSoft, location: 0),
                    .init(color: Tokens.accentFaint, location: 0.45),
                    .init(color: Tokens.accentFaint.opacity(0), location: 1),
                ], center: .center, startRadius: 0, endRadius: 170))
                .frame(width: 340, height: 340)
                .scaleEffect(x: 1, y: 0.68)
                .offset(y: 12)
            ForEach(Array(Self.books.enumerated()), id: \.offset) { index, book in
                let isHero = index == Self.hero
                let moves = !reduceMotion
                BookCover(relativePath: nil, paths: env.paths, height: book.height, title: book.title, asset: book.asset)
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
