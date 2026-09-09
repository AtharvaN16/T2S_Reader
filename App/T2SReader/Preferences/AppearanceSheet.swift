import SwiftUI
import T2SApp

/// Reader-specific appearance controls, also reached from the Reader overflow menu. Text size and
/// line height only apply while reading, so the Settings presentation hides them and shows the
/// app-wide theme picker and the read-along highlight.
struct AppearanceSheet: View {
    @Environment(AppEnvironment.self) private var env
    var showsTextControls: Bool = true

    var body: some View {
        @Bindable var preferences = env.preferences
        // The sliders plus two rows outgrow a medium detent, so the sheet scrolls and can be pulled to large.
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Highlight · the sentence and word being read").typeRole(.meta).foregroundStyle(Tokens.ink2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(HighlightTheme.allCases) { theme in
                                HighlightSwatch(theme: theme, selected: preferences.highlightTheme == theme) {
                                    preferences.highlightTheme = theme
                                }
                            }
                        }
                    }
                    // Swatches scroll out under the page margin instead of being cut off at it.
                    .scrollClipDisabled()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.section)
        }
        .presentationBackground(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
        // A sheet is its own presentation: it takes the root's colour scheme when it opens but does
        // not follow a change made while it is up — and this is the sheet the change is made from.
        .appTheme()
    }
}

/// One `HighlightTheme` as a miniature page: three text lines, the middle one on the sentence tint
/// with the word mark over it. Shapes, not text, so it reads at a glance and never wraps.
private struct HighlightSwatch: View {
    var theme: HighlightTheme
    var selected: Bool
    var action: () -> Void

    private static let corner = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                Text(theme.label).typeRole(.meta).foregroundStyle(selected ? Tokens.ink : Tokens.ink2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.label) highlight")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var preview: some View {
        // 5 pt plus the band's 5 pt reach past its line keeps the three lines 10 pt apart.
        VStack(alignment: .leading, spacing: 5) {
            line(70)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Tokens.highlightTint(theme))
                line(60)
            }
            .frame(height: 16)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Tokens.highlightWord(theme))
                    .frame(width: 28, height: 16)
            }
            line(64)
        }
        .padding(.horizontal, 10)
        .frame(width: 92, height: 72)
        .background(Tokens.raised, in: Self.corner)
        // Stroked inside the shape: a centred stroke would lose its top pixel to the scroll view's edge.
        .overlay(Self.corner.strokeBorder(selected ? Tokens.ink : Tokens.ink3, lineWidth: selected ? 2 : 1))
    }

    private func line(_ width: CGFloat) -> some View {
        Capsule().fill(Tokens.ink3).frame(width: width, height: 6)
    }
}
