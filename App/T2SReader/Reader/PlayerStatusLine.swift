// App/T2SReader/Reader/PlayerStatusLine.swift
import SwiftUI
import T2SApp

/// What the engine is doing, said once, above the chapter picker (owner, 2026-09-13). It used to
/// be an overlay across the clock row; the scope chip has that slot now, and the line reads better
/// up here anyway — clear of the transport, it is a note about the page rather than a label on the
/// controls.
///
/// Tinted rather than boxed, on the owner's word: `glow`, which the token comment reserves for a
/// state of the engine rather than a mark on the page, and which is exactly what both of these
/// are. It sits where the text is already dimmed by the `ground` fade, so a blue line at `pill`
/// weight is the brightest thing in its neighbourhood without needing a background to sit on.
///
/// The three dots are the ellipsis made honest: the strings no longer carry "…" as punctuation the
/// eye does not count, they carry a wave that says work is still going on.
struct PlayerStatusLine: View {
    var text: String

    var body: some View {
        // Dots over the words, both centred (owner, 2026-09-13). Stacked rather than trailing the
        // sentence, they stop reading as an ellipsis attached to the last word and become a small
        // indicator standing on its own — and the line no longer grows sideways as it animates.
        VStack(spacing: 5) {
            LoadingDots()
            Text(text)
        }
        .typeRole(.pill)                                                    // a step up from `meta`, in Medium
        .foregroundStyle(Tokens.glow)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Three dots breathing in sequence. Its own view so `.repeatForever` lives on state this view
/// owns — the same reason `TransportGlyph` is its own view: driven from a parent that redraws on
/// every tick of the clock beside it, a repeating animation is restarted on each redraw and never
/// gets anywhere. Nothing outside can change its inputs, so nothing outside can interrupt it.
private struct LoadingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    private static let dot: CGFloat = 5
    private static let period: TimeInterval = 0.5
    /// A third of the period between dots, so the wave reads as travel rather than as a flicker.
    private static let stagger: TimeInterval = 0.16

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: Self.dot, height: Self.dot)
                    .opacity(lit ? 1 : 0.25)
                    .animation(animation(delayedBy: Double(i) * Self.stagger), value: lit)
            }
        }
        // Reduce Motion leaves three even dots: still an ellipsis, just not a moving one.
        .opacity(reduceMotion ? 0.6 : 1)
        .onAppear { lit = !reduceMotion }
        .onChange(of: reduceMotion) { _, reduce in lit = !reduce }
        .accessibilityHidden(true)
    }

    /// Nil once the wave is over, so the settle back to rest is not caught by a repeating curve.
    private func animation(delayedBy delay: TimeInterval) -> Animation? {
        lit ? .easeInOut(duration: Self.period).repeatForever(autoreverses: true).delay(delay) : nil
    }
}
