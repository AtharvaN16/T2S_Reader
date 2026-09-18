import SwiftUI
import T2SApp

/// The soundscape picker alone on a sheet, for the sleep sheet's row (soundscape design §4.3): the
/// setting lives in the Reader's Preferences; this is a second door to the same room, not a
/// second room. Wears the book's paper as the sleep sheet does.
struct SoundscapeSheet: View {
    @Environment(AppEnvironment.self) private var env
    var wearsPaper: Bool

    private var palette: ReaderPalette { wearsPaper ? ReaderPalette(env.preferences.readerPaper) : .app }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Image(systemName: "cloud.rain")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(palette.ink3)
                    Text("Soundscape").typeRole(.sectionHeader).foregroundStyle(palette.ink)
                }
                .padding(.top, Spacing.margin)
                .padding(.bottom, Spacing.row)
                SoundscapePicker(showsTitle: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.margin)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .presentationBackground(palette.sheet)
        .appTheme()
        .environment(\.readerPalette, palette)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}
