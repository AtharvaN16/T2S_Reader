// App/T2SReader/Onboarding/VoicePill.swift
import SwiftUI
import T2SApp

/// The voice the reader is hearing, named once at the crown of the welcome's page (the owner,
/// 2026-09-17: "just show one voice pill at a time … and you can swipe anywhere on the screen").
///
/// This was a row of five pills, and before that a carousel of 72 pt coloured boxes along the
/// foot. Both made the picker the thing on the screen, when the thing on the screen is the passage
/// being read. One pill says who is reading in a glance, and the gesture that changes it is not on
/// the pill at all — `OnboardingCover` takes a drag anywhere on the page, so there is no small
/// target to find and the whole screen is the control. What is left here is a label.
///
/// It is still a button: once the passage has been heard through, a tap plays it again, and the
/// replay glyph appears inside the pill to say so.
///
/// The colour is `VoicePalette`'s, which the rim above reads too, so the light at the crown and the
/// pill under it are always the same hue.
struct VoicePill: View {
    /// A Kokoro voice name, `af_heart`.
    var voice: String
    var voices: [String]
    /// True once the passage has been heard through in this voice: the pill offers replay.
    var isFinished: Bool
    var onReplay: () -> Void

    static let height: CGFloat = 44

    var body: some View {
        let colour = VoicePalette.colour(for: voice, in: voices)
        return Button(action: onReplay) {
            HStack(spacing: 7) {
                if isFinished {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(VoicePalette.displayName(voice))
                    .typeRole(.pill)
                    // Keyed on the voice so the name cross-fades when the reader swipes, rather
                    // than one word being swapped for another under a capsule that slid to a new
                    // width. The capsule's own colour and width animate; the label dissolves.
                    .id(voice)
                    .transition(.opacity)
            }
            .foregroundStyle(Tokens.onAccent)
            .padding(.horizontal, 22)
            .frame(height: Self.height)
            .background(Capsule(style: .continuous).fill(colour))
            .shadow(color: colour.opacity(0.4), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.35), value: voice)
        .animation(.snappy, value: isFinished)
        .accessibilityLabel(isFinished
                            ? "\(VoicePalette.displayName(voice)), play again"
                            : VoicePalette.displayName(voice))
        .accessibilityHint("Swipe left or right anywhere to try another voice")
    }
}
