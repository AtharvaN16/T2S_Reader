// App/T2SReader/Onboarding/VoiceCarousel.swift
import SwiftUI
import T2SApp

/// The voice picker at the crown of the welcome's page: one compact pill per voice in a row that
/// scrolls sideways, the chosen one filled with its own colour and the rest quiet (design:
/// `docs/superpowers/specs/2026-09-16-onboarding-reel-welcome-page-design.md`; the owner,
/// 2026-09-16: "we can have the voice pills on the top of the screen, over a tall fade").
///
/// This was a carousel of 72 pt coloured containers along the foot, one at a time with the next
/// peeking in — right when the picker was the last thing on the screen and the reader's thumb was
/// already there. At the crown it has to answer a different question: the reader is looking at the
/// passage, and the row above it is a caption saying *this is the voice you are hearing, and here
/// are the others*. A row of pills says that in one glance where one big box at a time says it
/// over several swipes, and it leaves the passage the whole of the screen.
///
/// The pill on screen is the choice — the caller plays the passage in it, and Continue makes it
/// the default. A tap on another pill moves to it; a tap on the chosen one, once its passage has
/// been heard through, plays it again.
///
/// The colours are `VoicePalette`'s, which the glow above reads too, so the light at the crown and
/// the filled pill under it are always the same hue.
struct VoiceCarousel: View {
    /// Kokoro voice names, `af_heart`.
    var voices: [String]
    @Binding var selected: String
    /// True once the passage has been heard through in the chosen voice: the pill offers replay.
    var isFinished: Bool
    var onReplay: () -> Void

    @State private var scrolled: String?

    static let height: CGFloat = 40

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.grid) {
                ForEach(voices, id: \.self) { voice in
                    pill(voice)
                        .id(voice)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Spacing.margin)
        }
        .scrollIndicators(.hidden)
        // Aligned rather than paged: the row is a row, and a reader flicking it should be able to
        // land between two pills the way any pill row in the app does. The chosen pill is brought
        // to the centre when it changes, which is what keeps a tap at the far edge from leaving
        // the choice half off the screen.
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolled, anchor: .center)
        .frame(height: Self.height)
        .onChange(of: selected) { _, voice in
            if scrolled != voice { withAnimation(.snappy) { scrolled = voice } }
        }
        .onAppear { scrolled = selected }
    }

    /// One voice: its first name, filled with its own colour when it is the choice and quiet when
    /// it is not, with a replay glyph inside the chosen one once its passage has been heard.
    private func pill(_ voice: String) -> some View {
        let isSelected = voice == selected
        let colour = VoicePalette.colour(for: voice, in: voices)
        return Button {
            if isSelected { onReplay() } else { selected = voice }
        } label: {
            HStack(spacing: 6) {
                if isSelected, isFinished {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(VoicePalette.displayName(voice))
                    .typeRole(.pill)
            }
            .foregroundStyle(isSelected ? Tokens.onAccent : Tokens.ink)
            .padding(.horizontal, 16)
            .frame(height: Self.height)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(colour) : AnyShapeStyle(Tokens.surface))
            }
            // Only the chosen pill is lifted, and in its own colour: the row sits over the
            // passage, so an unlifted pill would read as a word in the text rather than a control.
            .shadow(color: isSelected ? colour.opacity(0.4) : .clear, radius: 10, y: 4)
            .animation(.snappy, value: isSelected)
            .animation(.snappy, value: isFinished)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected && isFinished
                            ? "\(VoicePalette.displayName(voice)), play again"
                            : VoicePalette.displayName(voice))
    }
}
