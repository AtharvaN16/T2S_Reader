// App/T2SReader/Root/PageIndicator.swift
import SwiftUI

/// Which of the three pages is up, as pagination marks rather than named icons (owner, 2026-09-12:
/// "remove the icons on the bottom bar, replace them with pagination dots and a bar for the current
/// page"): two dots and, for the page you are on, a bar.
///
/// The marks say *where* rather than *what*, which is what a pager wants — the pages are swiped, and
/// three labelled icons were a tab bar's promise the app does not keep. They are still buttons: each
/// wears a taller, wider target than the 7 pt it draws, so a mark can be tapped as well as swiped to.
///
/// **The move.** One spring (``motion``) drives the whole row, a tap and a swipe alike, and the bar
/// is not a separate thing that slides — every mark is the same capsule and only its width changes,
/// so the one growing and the two shrinking are a single gesture and the marks either side are
/// carried along by it rather than jumping to new places. A little bounce at the end, because it is
/// answering a swipe.
///
/// Half the height the icons needed, and the row is what `RootPager`'s bottom fill is solid through,
/// so the space goes to the mini-player standing lower above it.
struct PageIndicator: View {
    /// The row's height, which `RootPager`'s bottom fill is solid through.
    static let height: CGFloat = 22
    /// The mark: a dot this wide and tall, or — on the current page — a bar of ``bar`` by this.
    private static let dot: CGFloat = 7
    private static let bar: CGFloat = 22
    /// Half of it either side of every mark: the gap between them, and what makes a 7 pt dot a
    /// target worth aiming at.
    private static let reach: CGFloat = 7

    @Binding var page: RootPage

    /// Quick, and a touch of bounce at the end. One curve for the tap and the swipe both, so a page
    /// taken either way arrives the same.
    static let motion: Animation = .snappy(duration: 0.32, extraBounce: 0.12)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootPage.allCases, id: \.self) { p in
                let isCurrent = p == page
                Button {
                    withAnimation(Self.motion) { page = p }
                } label: {
                    Capsule()
                        .fill(isCurrent ? Tokens.ink : Tokens.ink3)
                        .frame(width: isCurrent ? Self.bar : Self.dot, height: Self.dot)
                        .padding(.horizontal, Self.reach)
                        .frame(height: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.title)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        // On the row, not only on the tap: a page taken by swiping the pager changes `page` without
        // going through the button, and the marks have to follow that too.
        .animation(Self.motion, value: page)
    }
}
