// App/T2SReader/Onboarding/VoiceList.swift
import SwiftUI
import T2SApp

/// The welcome's third beat: the voices as a list (the owner, 2026-09-18, with Queue's *Add
/// Podcasts* as the reference: "for the voice screen, I am thinking let us just keep a list").
///
/// A row per voice — a lozenge in the voice's own colour carrying its initial, the name, the
/// character line the voice picker already uses (`KokoroVoiceCatalog.personalities`), and a key on
/// the right that plays the passage in it. Tapping anywhere on the row chooses that voice and
/// plays it; the chosen row is marked and its key becomes a stop.
///
/// **What this replaced, and what went with it.** Beat three used to be the passage itself, set in
/// the Reader's own type, with the words lighting as they were spoken and the block following the
/// voice — the app's whole argument in one screen. A list cannot do that, and does two other
/// things instead: it shows that there is more than one voice, which one pill at a time could not,
/// and it says what each one is like before it is played. The sample still plays; it is just no
/// longer read along with.
///
/// The five here are the manifest's, not the catalogue's twenty-eight: these are the voices the
/// hero's passage has been rendered in, and a row with no clip behind it would be a row that does
/// nothing.
struct VoiceList: View {
    var voices: [String]
    @Binding var selected: String
    /// True while the chosen voice's passage is sounding.
    var isPlaying: Bool
    var onPlay: (String) -> Void
    var onStop: () -> Void

    static let rowHeight: CGFloat = 72
    static let markSize: CGFloat = 46

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(voices, id: \.self) { voice in
                row(voice)
            }
        }
    }

    private func row(_ voice: String) -> some View {
        let isSelected = voice == selected
        let colour = VoicePalette.colour(for: voice, in: voices)
        let sounding = isSelected && isPlaying
        return Button {
            if sounding { onStop() } else { selected = voice; onPlay(voice) }
        } label: {
            HStack(spacing: Spacing.grid + 4) {
                mark(voice, colour: colour)
                VStack(alignment: .leading, spacing: 2) {
                    Text(VoicePalette.displayName(voice))
                        .typeRole(.rowTitle)
                        .foregroundStyle(Tokens.ink)
                    Text(KokoroVoiceCatalog.personalities[voice] ?? "Natural and clear")
                        .typeRole(.meta)
                        .foregroundStyle(Tokens.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: Spacing.grid)
                // The trailing key is the reference's *Subscribe*: one affordance per row, always
                // in the same place, that says what tapping does without having to be read.
                Image(systemName: sounding ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isSelected ? Tokens.onAccent : Tokens.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isSelected ? AnyShapeStyle(colour) : AnyShapeStyle(Tokens.surface)))
            }
            .padding(.vertical, Spacing.grid + 2)
            .frame(minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
        .animation(.snappy, value: sounding)
        .accessibilityLabel(VoicePalette.displayName(voice))
        .accessibilityValue(isSelected ? "Chosen" : "")
        .accessibilityHint(sounding ? "Stop" : "Play a sample and choose this voice")
    }

    /// The voice's lozenge: its own colour, its initial, and a ring when it is the chosen one —
    /// the row's picture, standing in for the artwork the reference's podcasts have.
    private func mark(_ voice: String, colour: Color) -> some View {
        let isSelected = voice == selected
        return Text(VoicePalette.displayName(voice).prefix(1))
            .font(.custom("InterDisplay-Black", size: 20))
            .foregroundStyle(Tokens.onAccent)
            .frame(width: Self.markSize, height: Self.markSize)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(colour))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(colour.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                    .padding(-4)
            }
            .shadow(color: colour.opacity(isSelected ? 0.45 : 0), radius: 10, y: 4)
    }
}
