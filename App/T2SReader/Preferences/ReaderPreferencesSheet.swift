import SwiftUI
import T2SApp

/// The Reader's own settings, behind the `⋯`. It was "Appearance" until 2026-09-14 and held type
/// size, line height and the app-wide theme; the owner asked for the reading *behaviours* to live
/// beside them rather than in app Settings, where they would be a page away from the only screen
/// they describe — so it is "Preferences" now, and the sliders are one of its three parts.
///
/// Settings presents the same sheet with `showsReaderControls` off, and there it is still
/// "Appearance": the theme is the only thing in here that is not about a book being read, and a
/// slider that moves text nobody is looking at is a control without a subject.
///
/// The read-along highlight used to be picked here too. The swatches are gone (owner, 2026-09-12:
/// "remove the highlight section ... we no longer have it"); `highlightTheme` stays as the reader's
/// fixed tint, on its stored value or the `.amber` default.
struct ReaderPreferencesSheet: View {
    @Environment(AppEnvironment.self) private var env
    /// Everything that only means something while a book is open: the two sliders and the two
    /// switches. Off in Settings, which shows the theme alone.
    var showsReaderControls: Bool = true

    var body: some View {
        @Bindable var preferences = env.preferences
        // The sliders plus the theme row can outgrow a medium detent at the larger text sizes, so the
        // sheet scrolls and can be pulled to large.
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Text(showsReaderControls ? "Preferences" : "Appearance")
                    .typeRole(.sectionHeader)
                    .foregroundStyle(Tokens.ink)
                    .padding(.top, Spacing.section)
                if showsReaderControls {
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
                    // Two switches, both about what the Reader does rather than how it looks. Each
                    // carries a grey line saying what it governs — these are gestures and marks a
                    // reader may never have noticed, so the row has to name them before it can
                    // sensibly ask whether to keep them.
                    VStack(alignment: .leading, spacing: 20) {
                        toggle("Hold to change chapter",
                               detail: "Press and hold a skip button to jump a chapter.",
                               isOn: $preferences.holdSkipChangesChapter)
                        toggle("Bookmark marks on the bar",
                               detail: "Shows where this chapter's bookmarks are while you scrub.",
                               isOn: $preferences.showsBookmarkMarks)
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

    /// Settings' own row, which is a title over a grey line with the control at the far end.
    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).typeRole(.settingsRow).foregroundStyle(Tokens.ink)
                    .multilineTextAlignment(.leading)
                Text(detail).typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn).labelsHidden()
        }
    }
}
