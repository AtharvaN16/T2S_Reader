import SwiftUI
import T2SApp

/// Reader-specific appearance controls, also reached from the Reader overflow menu.
struct AppearanceSheet: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var preferences = env.preferences
        VStack(alignment: .leading, spacing: Spacing.section) {
            Text("Appearance")
                .typeRole(.sectionHeader)
                .foregroundStyle(Tokens.ink)
                .padding(.top, Spacing.section)
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
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme").typeRole(.meta).foregroundStyle(Tokens.ink2)
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
        .padding(.horizontal, Spacing.margin)
        .background(Tokens.raised)
        .presentationDetents([.medium])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}
