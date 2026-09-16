// App/T2SReader/Import/ImportGraphic.swift
import SwiftUI

/// The picture over the Import hub: the three ways in, standing as three objects over the same pool
/// of blue light the empty shelf uses — a notepad for words a reader writes or pastes, a browser
/// page for a link, and a book in front for a file. One object per row under it, so the picture
/// names the list rather than decorating it (owner, 2026-09-16, from the reference's "Bring your
/// shows to Brink"). No arrow and no app icon: the reference draws an arrow because it is moving a
/// library out of another app, and this page is not a migration — it is three kinds of thing
/// becoming one you can listen to.
///
/// They rise into place the way `EmptyShelf`'s fan does and then hold still. The shelf's hero keeps
/// a slow breath because it is the only thing on that page; here there are three rows below that
/// the eye has to reach, and a book breathing over them would keep pulling it back up.
struct ImportGraphic: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    /// The frame the picture stands in. Shorter than the empty shelf's 230: that page has nothing
    /// under its picture, and this one has to seat three rows and a headline on the same screen.
    static let height: CGFloat = 196

    private static let coverHeight: CGFloat = 126
    private static let sheetHeight: CGFloat = 106
    /// How far out from the middle the two sheets stand. The book is `BookCover.ratio` × 126 ≈ 84
    /// wide and the sheets are `SheetCover.ratio` × 106 ≈ 76, so at 74 each pair overlaps by about a
    /// third — enough to read as one group, not so much that a sheet becomes a sliver.
    private static let spread: CGFloat = 74

    var body: some View {
        let moves = !reduceMotion
        ZStack {
            Pool()
            // The notepad — "Write or paste text". No `sourceURL`, so `SheetCover` draws its cream
            // paper and binding rather than a browser window.
            sheet(SheetCover(title: "Notes", sourceURL: nil, height: Self.sheetHeight),
                  angle: -14, x: -Self.spread, y: 10, delay: 0, moves: moves)
            // The web page — "Paste a link". Any host would do; this one is short enough that the
            // address pill in the chrome strip does not truncate at 106 pt.
            sheet(SheetCover(title: "Article", sourceURL: URL(string: "https://www.newyorker.com"), height: Self.sheetHeight),
                  angle: 14, x: Self.spread, y: 10, delay: 0.12, moves: moves)
            // The book — "Upload a file". The empty shelf's own stock cover, drawn as every book in
            // the app is drawn (the mockup: hinge, sheen, shadow), turned a little toward the reader.
            sheet(BookCover(relativePath: nil, paths: env.paths, height: Self.coverHeight,
                            title: "Circe", tilt: settled || !moves ? CGPoint(x: 0, y: -4) : .zero,
                            asset: "EmptyCoverCirce"),
                  angle: 0, x: 0, y: 0, delay: 0.26, moves: moves)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onAppear { settled = true }
    }

    /// One object of the three: low, small and square-on to start, springing up to its angle and
    /// place. With Reduce Motion on nothing moves — the three only fade in together.
    private func sheet<Object: View>(_ object: Object, angle: Double, x: CGFloat, y: CGFloat,
                                     delay: Double, moves: Bool) -> some View {
        object
            .rotationEffect(.degrees(settled || !moves ? angle : angle * 0.3))
            .offset(x: settled || !moves ? x : x * 0.5,
                    y: settled || !moves ? y : y + 40)
            .scaleEffect(settled || !moves ? 1 : 0.9)
            .opacity(settled ? 1 : 0)
            .animation(moves ? .spring(response: 0.66, dampingFraction: 0.76).delay(delay)
                             : .easeOut(duration: 0.35), value: settled)
    }
}
