import SwiftUI
import T2SApp

/// Reader-specific appearance controls, also reached from the Reader overflow menu. Text size and
/// line height only apply while reading, so the Settings presentation hides them and shows only the
/// app-wide theme picker.
///
/// The read-along highlight used to be picked here, in both presentations. The swatches are gone
/// (owner, 2026-09-12: "remove the highlight section ... we no longer have it"); `highlightTheme`
/// stays as the reader's fixed tint, on its stored value or the `.amber` default.
struct AppearanceSheet: View {
    @Environment(AppEnvironment.self) private var env
    var showsTextControls: Bool = true

    var body: some View {
        @Bindable var preferences = env.preferences
        // The sliders plus the theme row can outgrow a medium detent at the larger text sizes, so the
        // sheet scrolls and can be pulled to large.
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Text("Appearance")
                    .typeRole(.sectionHeader)
                    .foregroundStyle(Tokens.ink)
                    .padding(.top, Spacing.section)
                if showsTextControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Text size").typeRole(.meta).foregroundStyle(Tokens.ink2)
                        Slider(value: $preferences.textScale, in: ReaderPreferences.textScaleRange, step: 0.1)
                            .tint(Tokens.ink)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Line height").typeRole(.meta).foregroundStyle(Tokens.ink2)
                        Slider(value: $preferences.lineHeight, in: ReaderPreferences.lineHeightRange, step: 0.1)
                            .tint(Tokens.ink)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Theme · applies to the whole app").typeRole(.meta).foregroundStyle(Tokens.ink2)
                    HStack(spacing: Spacing.grid) {
                        ForEach(ReaderTheme.allCases, id: \.self) { theme in
                            Pill(label: theme.rawValue.capitalized, style: preferences.theme == theme ? .selected : .soft) {
                                preferences.theme = theme
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.section)
        }
        .presentationBackground(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}
