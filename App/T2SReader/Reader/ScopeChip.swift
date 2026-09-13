// App/T2SReader/Reader/ScopeChip.swift
import SwiftUI
import T2SApp

/// The scrubber's scope switch (2026-09-13), centred under the bar: four short bars for the whole
/// book, one unbroken bar for the chapter you are in. Both cells are always visible and the filled
/// one is the scope you are *in* — a single chip that flips has to choose between naming its state
/// and naming its destination, and the two read identically while meaning opposite things.
///
/// Wordless on purpose. The chapter row six points above already reads "Chp 2: …", so a chip
/// labelled "Chapter" would be repeating a word at twice the size; and the glyphs are not icons
/// standing for the idea of a book, they are miniatures of the two bars themselves, sitting
/// directly under the bar they switch.
struct ScopeChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scope: ScrubberScope
    var onChange: (ScrubberScope) -> Void

    private static let cell = CGSize(width: 30, height: 22)
    /// How far the track stands proud of the thumb on every side.
    private static let inset: CGFloat = 2
    /// The chip settles before the bar arrives (the bar runs at 0.34), so the bar reads as the
    /// consequence of the tap rather than something happening alongside it.
    private static let slide = Animation.spring(response: 0.28, dampingFraction: 0.72)

    var body: some View {
        // Read once here rather than inside the keyframe closure: that closure is `@Sendable`, and
        // an environment value is main-actor isolated, so it has to be captured as a plain Bool.
        let reduce = reduceMotion
        return Button {
            onChange(scope.other)
        } label: {
            ZStack(alignment: .leading) {
                // A track under both cells and a thumb on the live one — the shape of a switch
                // rather than two loose glyphs (owner, 2026-09-13). `surface` is the app's filled
                // control on `ground`; `raised` is the step above it, so the thumb reads as
                // sitting in the track in light and inset into it in dark.
                Capsule()
                    .fill(Tokens.surface)
                    .frame(width: Self.cell.width * 2 + Self.inset * 2, height: Self.cell.height + Self.inset * 2)
                Capsule()
                    .fill(Tokens.raised)
                    .frame(width: Self.cell.width, height: Self.cell.height)
                    .offset(x: Self.inset + (scope == .chapter ? Self.cell.width : 0))
                HStack(spacing: 0) {
                    cell(BookGlyph(), lit: scope == .book)
                    cell(ChapterGlyph(), lit: scope == .chapter)
                }
                .offset(x: Self.inset)
            }
            .animation(reduce ? .easeInOut(duration: 0.2) : Self.slide, value: scope)
            // The tactile half of the tap: the chip swells and settles where it stands. Scale
            // only — the chip is centred on the clock row and must never be seen to move, or the
            // eye reads it as drifting with the clocks rather than as a fixed control.
            .keyframeAnimator(initialValue: 1.0, trigger: scope) { view, scale in
                view.scaleEffect(reduce ? 1 : scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.12, duration: 0.12, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.24, spring: .bouncy)
                }
            }
            .frame(width: Self.cell.width * 2 + Self.inset * 2, height: Self.cell.height + Self.inset * 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Progress bar")
        .accessibilityValue(scope == .book ? "Whole book" : "This chapter")
        .accessibilityHint("Switches what the progress bar spans")
    }

    private func cell(_ glyph: some View, lit: Bool) -> some View {
        glyph
            .foregroundStyle(lit ? Tokens.ink : Tokens.ink2)
            .frame(width: Self.cell.width, height: Self.cell.height)
            // Opacity and colour on a spring visibly wobble; only the capsule should feel sprung.
            .animation(.linear(duration: 0.16), value: lit)
    }
}

/// The segmented bar, in miniature: uneven chapters with the gaps between them.
private struct BookGlyph: View {
    var body: some View {
        HStack(spacing: 1.5) {
            bar(3); bar(6); bar(3.5); bar(2)
        }
    }

    private func bar(_ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 0.5, style: .continuous)
            .fill(.foreground)
            .frame(width: width, height: 3)
    }
}

/// One chapter, unbroken and rounded — the bar chapter scope draws.
private struct ChapterGlyph: View {
    var body: some View {
        Capsule().fill(.foreground).frame(width: 17, height: 3)
    }
}
