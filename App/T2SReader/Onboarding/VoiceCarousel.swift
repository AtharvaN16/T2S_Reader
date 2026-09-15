// App/T2SReader/Onboarding/VoiceCarousel.swift
import SwiftUI
import T2SApp

/// The voice picker, floating over the lower part of the read-along text: one big rounded-
/// rectangle container at a time, each its own colour, the next peeking in faded at the edge,
/// swiped between and snapped to the centre (the owner, 2026-09-15: "make each pill rounded
/// rectangular containers each with different colors … the voice boxes are over the text"). The
/// container on screen is the choice — the caller plays the passage in it, and Continue makes it
/// the default. When the voice has finished, a replay glyph appears inside it and a tap plays it
/// again.
struct VoiceCarousel: View {
    /// Kokoro voice names, `af_heart`.
    var voices: [String]
    @Binding var selected: String
    /// True once the passage has been heard through in the chosen voice: the container offers replay.
    var isFinished: Bool
    var onReplay: () -> Void

    @State private var scrolled: String?

    /// The container's share of the width; what is left either side is the peek.
    static let boxShare: CGFloat = 0.72
    static let boxHeight: CGFloat = 72
    static let cornerRadius: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * Self.boxShare
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.grid + 4) {
                    ForEach(voices, id: \.self) { voice in
                        box(voice, width: width)
                            .id(voice)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.55)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.92)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolled, anchor: .center)
            .contentMargins(.horizontal, (geo.size.width - width) / 2, for: .scrollContent)
            .onChange(of: scrolled) { _, voice in
                if let voice, voice != selected { selected = voice }
            }
            .onChange(of: selected) { _, voice in
                if scrolled != voice { withAnimation(.snappy) { scrolled = voice } }
            }
            .onAppear { scrolled = selected }
        }
        .frame(height: Self.boxHeight)
    }

    /// The big container: its own colour, the voice's name, and once heard, a replay glyph. A tap
    /// on the centred one replays; a tap on the peeking one selects it. Lifted with a shadow of
    /// its own colour, since it sits over the text rather than beside it.
    private func box(_ voice: String, width: CGFloat) -> some View {
        let isSelected = voice == selected
        let colour = Self.colour(for: voice, in: voices)
        return Button {
            if isSelected { onReplay() } else { selected = voice }
        } label: {
            HStack(spacing: Spacing.grid) {
                Text(Self.displayName(voice))
                    .typeRole(.groupTitle)
                if isSelected, isFinished {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundStyle(Tokens.onAccent)
            .frame(width: width, height: Self.boxHeight)
            .background(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).fill(colour))
            .shadow(color: colour.opacity(0.45), radius: 12, y: 6)
            .animation(.snappy, value: isFinished)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected && isFinished ? "\(Self.displayName(voice)), play again" : Self.displayName(voice))
    }

    /// Each voice its own colour, spaced around the wheel by its place in the row so neighbours
    /// never look alike — scales to any number of voices, since a book added to the manifest adds
    /// a voice to this row too.
    static func colour(for voice: String, in voices: [String]) -> Color {
        let index = voices.firstIndex(of: voice) ?? 0
        let count = max(voices.count, 1)
        let hue = (Double(index) / Double(count) + 0.02).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.58, brightness: 0.62)
    }

    /// `af_heart` → `Heart`.
    static func displayName(_ voice: String) -> String {
        let stem = voice.split(separator: "_").last.map(String.init) ?? voice
        return stem.prefix(1).uppercased() + stem.dropFirst()
    }
}
