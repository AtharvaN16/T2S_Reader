import SwiftUI
import T2SApp

/// Reader-specific appearance controls, also reached from the Reader overflow menu. Text size and
/// line height only apply while reading, so the Settings presentation hides them and shows just
/// the app-wide theme picker.
struct AppearanceSheet: View {
    @Environment(AppEnvironment.self) private var env
    var showsTextControls: Bool = true

    var body: some View {
        @Bindable var preferences = env.preferences
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
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Spacing.margin)
        .presentationBackground(Tokens.raised)
        .presentationDetents([.medium])
        .presentationCornerRadius(Spacing.sheetCorner)
        // A sheet is its own presentation: it takes the root's colour scheme when it opens but does
        // not follow a change made while it is up — and this is the sheet the change is made from.
        .appTheme()
    }
}
