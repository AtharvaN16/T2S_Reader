// App/T2SReader/Reader/PlayerStatusLine.swift
import SwiftUI
import T2SApp

/// What the engine is doing, said once, above the chapter picker (owner, 2026-09-13). It used to
/// be an overlay across the clock row; the scope chip has that slot now, and the line reads better
/// up here anyway — clear of the transport, it is a note about the page rather than a label on the
/// controls.
///
/// `ink` on a `surface` capsule (owner, 2026-09-13). It stopped needing a colour of its own once
/// it had a floor of its own: `ink2` grey failed up here because it was grey on dimmed grey words,
/// and `glow` was tried next, but an opaque fill answers the same problem without spending the
/// accent — and `glow`'s own token comment reserves it for the warm-up's light rather than for
/// every line that mentions the engine.
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
        .foregroundStyle(Tokens.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        // A `surface` capsule, the same fill and the same fully-rounded shape as the voice chip
        // and the tool circles a few rows below, so the line reads as one of the app's own objects
        // rather than as a card dropped on the page. Fully rounded rather than a rounded rectangle
        // on the owner's word (2026-09-13).
        //
        // Opaque, because tinting alone did not hold: the fade only reaches ~30% by here, and a
        // translucent blue — `glowFaint`, `glowSoft`, `glow` at a third — still let the sentence
        // behind read through, which is a highlighter over words rather than a surface under them.
        .background(Tokens.surface, in: Capsule())
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
