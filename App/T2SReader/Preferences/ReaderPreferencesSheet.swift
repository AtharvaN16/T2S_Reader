import SwiftUI
import T2SApp

/// The Reader's own settings, behind the `⋯`. It was "Appearance" until 2026-09-14 and held type
/// size, line height and the app-wide theme; the owner asked for the reading *behaviours* to live
/// beside them rather than in app Settings, where they would be a page away from the only screen
/// they describe — so it is "Preferences" now, and the sliders are one of its three parts.
///
/// Settings presented this same sheet with the Reader's controls hidden until 2026-09-19, when its
/// Appearance became a sheet of its own (`AppearanceSheet`, with the app icon in it). The light and
/// dark pills here still move the app-wide switch — it is the only thing in here that is not about
/// a book being read, and the paper picker under it needs it close by.
///
/// The read-along highlight used to be picked here too. The swatches are gone (owner, 2026-09-12:
/// "remove the highlight section ... we no longer have it"); `highlightTheme` stays as the reader's
/// fixed tint, on its stored value or the `.amber` default.
struct ReaderPreferencesSheet: View {
    @Environment(AppEnvironment.self) private var env
    /// The Reader's paper. The sheet that chooses a paper had better be drawn on one (owner,
    /// 2026-09-14) — and from Settings, where there is no Reader, this is the app's own greys.
    /// Consulted while the app-wide switch says `system`; see `showsDarkFaces`.
    @Environment(\.colorScheme) private var scheme

    /// The sheet wears the book's paper. Read from the model here rather than handed in, so
    /// changing the paper — or the light behind it — repaints the sheet that is doing the changing
    /// (owner, 2026-09-14).
    private var palette: ReaderPalette { ReaderPalette(env.preferences.readerPaper) }

    var body: some View {
        @Bindable var preferences = env.preferences
        // The sliders plus the theme row can outgrow a medium detent at the larger text sizes, so the
        // sheet scrolls and can be pulled to large.
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Text("Preferences")
                    .typeRole(.sectionHeader)
                    .foregroundStyle(palette.ink)
                    .padding(.top, Spacing.section)
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
                //
                // Light and dark come first because they decide what the papers under them can
                // even look like (owner, 2026-09-14: "you should be able to switch between app
                // level light and dark, which then makes the reader theme easier to select").
                // A swatch shows one face now — the one you are in — so the way to see the
                // other eight is to stand in it.
                modes($preferences.theme)
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
                // How the book sounds, after how it looks and what it does (soundscape design
                // §2.6): the third part, and the one a reader would look for here.
                SoundscapePicker()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.section)
        }
        .presentationBackground(palette.sheet)
        .appTheme()                                                    // this sheet owns the switch; it had better follow it
        .environment(\.readerPalette, palette)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }

    /// Light or dark, app-wide — the same switch that used to be called Theme, and still the thing
    /// that governs every screen. No `System` pill here (owner, 2026-09-14): a paper is an explicit
    /// choice, and a page that changed under the reader at sunset would change which eight swatches
    /// they were looking at with it. System is offered in Settings' Appearance instead (2026-09-19),
    /// and a reader who took it sees the pill lit for the face the device is showing; a tap on
    /// either pill then makes that face explicit.
    @ViewBuilder private func modes(_ choice: Binding<ReaderTheme>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Light and dark").typeRole(.meta).foregroundStyle(palette.ink2)
            HStack(spacing: Spacing.grid) {
                ForEach([ReaderTheme.light, .dark], id: \.self) { theme in
                    modePill(theme.rawValue.capitalized,
                             glyph: theme == .light ? "sun.max.fill" : "moon.fill",
                             isOn: (theme == .dark) == showsDarkFaces) {
                        withAnimation(.snappy(duration: 0.2)) { choice.wrappedValue = theme }
                    }
                }
            }
        }
    }

    /// `Pill`'s shape in the paper's own colours — the app's `Pill` is drawn in `Tokens`, and on a
    /// sepia sheet the app's greys are a different object arriving from another room.
    private func modePill(_ label: String, glyph: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: glyph).font(.system(size: 12, weight: .semibold))
                Text(label).typeRole(.pill)
            }
            .lineLimit(1)
            .foregroundStyle(isOn ? palette.page : palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isOn ? palette.ink : palette.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// The sixteen papers, in their two families (palette:
    /// `docs/design/2026-09-14-reader-papers-16.html`; the picker: `…-paper-picker.html`). Zen
    /// first, because a book is the ordinary case; pop under it, under its own word.
    ///
    /// One face per swatch — the one the app is in — and one letter in that face's ink. The split
    /// chip that came before showed a paper, its night face, and what text looked like on both, at
    /// 56 pt: four regions a swatch, sixteen times (owner, 2026-09-14: "how many colors are there
    /// 4?"). The letter stays because at night it is the *only* part that differs: eight quiet
    /// papers in the dark are eight near-blacks, and what tells Sepia from Rose is the cream
    /// against the pink-white. The name goes to the heading, where one of them is enough.
    @ViewBuilder private func papers(_ choice: Binding<ReaderPaper>) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // One line for the section, the chosen paper's name, and the way back. `Paper` is the
            // page the app has always drawn, so it says so rather than repeating its own name
            // (owner, 2026-09-14) — and while you are anywhere else, the same slot is the door
            // home. A reader who tried Magenta at midnight should not have to remember which of
            // sixteen they started on.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Paper").typeRole(.meta).foregroundStyle(palette.ink2)
                Text(choice.wrappedValue == .paper ? "· Default" : "· \(choice.wrappedValue.title)")
                    .typeRole(.meta).foregroundStyle(palette.ink)
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
                if choice.wrappedValue != .paper {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { choice.wrappedValue = .paper }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold))
                            Text("Default").typeRole(.fine)
                        }
                        .foregroundStyle(palette.ink2)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(palette.surface, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to the default paper")
                    .transition(.opacity)
                }
            }
            ForEach([ReaderPaper.Family.zen, .pop], id: \.self) { family in
                VStack(alignment: .leading, spacing: 12) {
                    Text(family == .zen ? "Zen" : "Pop")
                        .typeRole(.fine).foregroundStyle(palette.ink2)
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

    /// Which face a swatch shows, and which pill is lit: the one the app's own light/dark switch
    /// has chosen, and the device's answer while that switch says `system`.
    private var showsDarkFaces: Bool {
        switch env.preferences.theme {
        case .light: return false
        case .dark: return true
        case .system: return scheme == .dark
        }
    }

    private func swatch(_ paper: ReaderPaper, isOn: Bool, action: @escaping () -> Void) -> some View {
        let faces = ReaderPalette.swatch(paper)
        let page = showsDarkFaces ? faces.dark : faces.light
        let ink = showsDarkFaces ? faces.darkInk : faces.lightInk
        return Button(action: action) {
            Text("Aa")
                .font(.custom("Inter-Bold", size: 17))
                .foregroundStyle(ink)
                .frame(width: 52, height: 52)
                .background(page, in: Circle())
                // A hairline, or Mono's white face on a white sheet is nothing at all.
                .overlay { Circle().strokeBorder(Tokens.edge, lineWidth: 1) }
                .overlay {
                    Circle().strokeBorder(palette.ink, lineWidth: 2.5)
                        .padding(-4)
                        .opacity(isOn ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
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
