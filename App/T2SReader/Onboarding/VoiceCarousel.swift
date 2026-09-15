// App/T2SReader/Onboarding/VoiceCarousel.swift
import SwiftUI
import T2SApp

/// The voice row under the hero's lines: one pill per voice, swiped or tapped, the chosen one in
/// `selected` style, with a "play again" beside it (the owner, 2026-09-14: "the different voices
/// as pills swipable with play again like a carousel"). Choosing a voice is the caller's cue to
/// play the passage in it; the row itself only holds the choice.
struct VoiceCarousel: View {
    /// Kokoro voice names, `af_heart`.
    var voices: [String]
    @Binding var selected: String
    var onPlayAgain: () -> Void

    @State private var scrolled: String?

    var body: some View {
        VStack(spacing: Spacing.grid + 4) {
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.grid) {
                    ForEach(voices, id: \.self) { voice in
                        Pill(label: Self.displayName(voice), style: voice == selected ? .selected : .soft) {
                            withAnimation(.snappy) { scrolled = voice }
                            selected = voice
                        }
                        .id(voice)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolled, anchor: .center)
            .contentMargins(.horizontal, Spacing.margin, for: .scrollContent)
            .onChange(of: scrolled) { _, voice in
                if let voice, voice != selected { selected = voice }
            }
            .onAppear { scrolled = selected }
            Pill(label: "Play again", glyph: "arrow.counterclockwise", style: .soft, action: onPlayAgain)
        }
    }

    /// `af_heart` → `Heart`.
    static func displayName(_ voice: String) -> String {
        let stem = voice.split(separator: "_").last.map(String.init) ?? voice
        return stem.prefix(1).uppercased() + stem.dropFirst()
    }
}
