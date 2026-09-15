// App/T2SReader/Onboarding/VoiceCarousel.swift
import SwiftUI
import T2SApp

/// The voice picker under the hero's lines: one big pill at a time, the next peeking in faded at
/// the edge, swiped between and snapped to the centre (the owner, 2026-09-15: "show only one big
/// voice pill at a time, with the next pill visible but faded, swipe between"). The pill on
/// screen is the choice — the caller plays the passage in it, and Continue makes it the default.
/// When the voice has finished, a replay glyph appears inside the pill and a tap plays it again.
struct VoiceCarousel: View {
    /// Kokoro voice names, `af_heart`.
    var voices: [String]
    @Binding var selected: String
    /// True once the passage has been heard through in the chosen voice: the pill offers replay.
    var isFinished: Bool
    var onReplay: () -> Void

    @State private var scrolled: String?

    /// The pill's share of the width; what is left either side is the peek.
    static let pillShare: CGFloat = 0.72
    static let pillHeight: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * Self.pillShare
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.grid + 4) {
                    ForEach(voices, id: \.self) { voice in
                        pill(voice, width: width)
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
        .frame(height: Self.pillHeight)
    }

    /// The big pill: the voice's name, and once heard, a replay glyph at its end. A tap replays.
    private func pill(_ voice: String, width: CGFloat) -> some View {
        let isSelected = voice == selected
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
            .foregroundStyle(isSelected ? Tokens.ground : Tokens.ink)
            .frame(width: width, height: Self.pillHeight)
            .background(Capsule().fill(isSelected ? Tokens.ink : Tokens.surface))
            .animation(.snappy, value: isFinished)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected && isFinished ? "\(Self.displayName(voice)), play again" : Self.displayName(voice))
    }

    /// `af_heart` → `Heart`.
    static func displayName(_ voice: String) -> String {
        let stem = voice.split(separator: "_").last.map(String.init) ?? voice
        return stem.prefix(1).uppercased() + stem.dropFirst()
    }
}
