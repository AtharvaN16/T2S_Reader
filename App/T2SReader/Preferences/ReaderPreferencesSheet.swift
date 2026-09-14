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
    /// The Reader's paper. The sheet that chooses a paper had better be drawn on one (owner,
    /// 2026-09-14) — and from Settings, where there is no Reader, this is the app's own greys.
    @Environment(\.readerPalette) private var palette
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
                    .foregroundStyle(palette.ink)
                    .padding(.top, Spacing.section)
                if showsReaderControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Text size").typeRole(.meta).foregroundStyle(palette.ink2)
                        Slider(value: $preferences.textScale, in: ReaderPreferences.textScaleRange, step: 0.1)
                            .tint(palette.ink)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Line height").typeRole(.meta).foregroundStyle(palette.ink2)
                        Slider(value: $preferences.lineHeight, in: ReaderPreferences.lineHeightRange, step: 0.1)
                            .tint(palette.ink)
                    }
                    // Under the two sliders rather than under everything (owner, 2026-09-14):
                    // type size, line height and the page's colour are the three things about how
                    // the book *looks*, and the switches below them are about what it does.
                    papers($preferences.readerPaper)
                    // Two switches, both about what the Reader does rather than how it looks. Each
                    // carries a grey line saying what it governs — these are gestures and marks a
                    // reader may never have noticed, so the row has to name them before it can
                    // sensibly ask whether to keep them.
                    VStack(alignment: .leading, spacing: 20) {
                        toggle("Hold to change chapter",
                               detail: "Press and hold the skip buttons to jump chapters.",
                               isOn: $preferences.holdSkipChangesChapter)
                        toggle("Bookmark positions",
                               detail: "Shows the bookmarks' positions on the scrubber.",
                               isOn: $preferences.showsBookmarkMarks)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Theme · applies to the whole app").typeRole(.meta).foregroundStyle(palette.ink2)
                        HStack(spacing: Spacing.grid) {
                            ForEach(ReaderTheme.allCases, id: \.self) { theme in
                                Pill(label: theme.rawValue.capitalized,
                                     style: preferences.theme == theme ? .selected : .soft) {
                                    preferences.theme = theme
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.section)
        }
        .presentationBackground(palette.sheet)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }

    /// The sixteen papers, in their two families (palette:
    /// `docs/design/2026-09-14-reader-papers-16.html`). Zen first, because a book is the ordinary
    /// case; pop under it, under its own word, because choosing one is choosing something else.
    ///
    /// Each swatch is split down the diagonal — the paper's lit face and its unlit one. A paper is
    /// a hue, and the phone still says whether it is day: showing one face would promise a page the
    /// reader might never see.
    @ViewBuilder private func papers(_ choice: Binding<ReaderPaper>) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach([ReaderPaper.Family.zen, .pop], id: \.self) { family in
                VStack(alignment: .leading, spacing: 11) {
                    Text(family == .zen ? "Paper" : "Paper · loud")
                        .typeRole(.meta).foregroundStyle(palette.ink2)
                    // Eight to a family: four and four at phone width, and one row of eight on
                    // anything wider.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                              spacing: 14) {
                        ForEach(ReaderPaper.all(family), id: \.self) { paper in
                            swatch(paper, isOn: choice.wrappedValue == paper) {
                                withAnimation(.snappy(duration: 0.2)) { choice.wrappedValue = paper }
                            }
                        }
                    }
                }
            }
        }
    }

    private func swatch(_ paper: ReaderPaper, isOn: Bool, action: @escaping () -> Void) -> some View {
        let faces = ReaderPalette.swatch(paper)
        return Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    faces.light
                    // The unlit face, cut in under the diagonal.
                    faces.dark.clipShape(SwatchHalf())
                    // One letter, in each face's own ink, so the swatch says what *text* looks like
                    // on this paper rather than only what the paper is.
                    HStack(spacing: 0) {
                        Text("A").foregroundStyle(faces.lightInk)
                        Text("a").foregroundStyle(faces.darkInk)
                    }
                    .font(.custom("Inter-Bold", size: 17))
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Tokens.edge, lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(palette.ink, lineWidth: 2.5)
                        .padding(-4)
                        .opacity(isOn ? 1 : 0)
                }
                Text(paper.title).typeRole(.fine).foregroundStyle(isOn ? palette.ink : palette.ink2)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(paper.title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// Settings' own row, which is a title over a grey line with the control at the far end.
    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).typeRole(.settingsRow).foregroundStyle(palette.ink)
                    .multilineTextAlignment(.leading)
                Text(detail).typeRole(.meta).foregroundStyle(palette.ink2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn).labelsHidden()
        }
    }
}

/// The lower-right triangle of a swatch: the paper's unlit face, cut in under the diagonal.
private struct SwatchHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
