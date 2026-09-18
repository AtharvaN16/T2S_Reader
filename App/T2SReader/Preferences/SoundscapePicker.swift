import SwiftUI
import T2SApp

/// The Reader's soundscape (soundscape design §4.3): a wrapping row of pills, Off first, and the
/// bed's volume under them. One view with two hosts — the last part of the Preferences sheet,
/// where it is how the book *sounds* after how it looks and what it does, and alone on
/// `SoundscapeSheet` for the sleep sheet's row. A tap is the choice; every tap and every slider
/// move auditions the bed for a few seconds if the book is paused, so the choice is heard where
/// it is made. The pills are the sheet's own `modePill` form: the paper's colours, so they belong
/// to the sheet they sit on rather than arriving in the app's greys.
struct SoundscapePicker: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.readerPalette) private var palette
    /// The "Soundscape" label over the pills; off on the sheet that carries the word as its title.
    var showsTitle: Bool = true

    var body: some View {
        @Bindable var soundscape = env.soundscape
        let isOff = soundscape.choice == nil
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                Text("Soundscape").typeRole(.meta).foregroundStyle(palette.ink2)
            }
            FlowRow(spacing: Spacing.grid, lineSpacing: Spacing.grid) {
                pill("Off", glyph: "speaker.slash", isOn: isOff) {
                    Task { await soundscape.choose(nil) }
                }
                ForEach(Soundscape.all) { option in
                    pill(option.title, glyph: option.glyph, isOn: soundscape.choice == option) {
                        Task { await soundscape.choose(option) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Volume").typeRole(.meta).foregroundStyle(palette.ink2)
                Slider(value: $soundscape.volume, in: 0...1) { _ in soundscape.audition() }
                    .tint(palette.ink)
                    .accessibilityLabel("Volume")
                    // `onEditingChanged` fires at drag start and end, which VoiceOver's swipe-up/
                    // swipe-down adjustment never triggers — this is what auditions for that reader.
                    .onChange(of: soundscape.volume) { soundscape.audition() }
            }
            .padding(.top, 8)
            .opacity(isOff ? 0.3 : 1)
            .disabled(isOff)
            .animation(.easeInOut(duration: 0.2), value: isOff)
            Text("Plays softly under the voice while the book is read.")
                .typeRole(.fine)
                .foregroundStyle(palette.ink2)
        }
    }

    private func pill(_ label: String, glyph: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: glyph).font(.system(size: 12, weight: .semibold))
                Text(label).typeRole(.pill)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isOn ? palette.page : palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isOn ? palette.ink : palette.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
