import SwiftUI
import T2SApp

/// Sleep-timer sheet with time and chapter-end options (spec §2.4.5).
///
/// The owner's reference (2026-09-12) is a centred sheet: the moon over its own title, the options
/// as a grid of tiles inside one grey card rather than a wrapping row of chips, and the one action
/// a full-width key at the foot. Our own elements do the work — `Tokens`, the `.selected` chip's
/// ink fill, the blue `RaisedButton` — so it is the podcast app's *shape*, not its paint.
///
/// The key sits on the floor of the sheet rather than under the card (owner, 2026-09-12), with the
/// air between them doing what the instruction line used to: nothing else is asked of you here, so
/// there is nothing left to explain.
struct SleepTimerSheet: View {
    @Environment(AppEnvironment.self) private var env
    /// True when the Reader presented this, and so when it should wear the book's paper.
    var wearsPaper = false

    /// Read from the model on every pass rather than taken from the environment at presentation
    /// (owner, 2026-09-14: "the UI sheets does not update when switching"). A sheet is its own
    /// presentation: a value handed to it when it opened is the value it keeps, and changing the
    /// paper or the light behind it left every sheet painted in the old one.
    private var palette: ReaderPalette { wearsPaper ? ReaderPalette(env.preferences.readerPaper) : .app }
    @Environment(\.dismiss) private var dismiss
    @State private var selected: SleepOption = .minutes(30)

    var body: some View {
        let timer = env.sleepTimer
        let caption = timer.caption
        VStack(spacing: 0) {
            // The scroll view is what holds the key to the floor: it takes whatever room is left
            // over, so the air above the key grows with the phone rather than the key drifting up
            // to meet the card. On a short screen, or at the accessibility text sizes, the same
            // view scrolls rather than clipping its last row — a medium detent is a fraction of
            // the screen, and the grid at its new height nearly fills one on a small phone.
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(palette.ink3)
                        Text("Sleep timer").typeRole(.sectionHeader).foregroundStyle(palette.ink)
                    }
                    .padding(.top, Spacing.margin)
                    .padding(.bottom, Spacing.row)

                    if let caption {
                        Text(caption).typeRole(.playerTitle).foregroundStyle(palette.ink)
                    } else {
                        OptionGrid(options: SleepOption.all, selected: $selected)
                    }
                }
                .padding(.bottom, Spacing.row)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            if caption != nil {
                Pill(label: "Cancel timer", style: .soft, fillsWidth: true) {
                    timer.cancel()
                    dismiss()
                }
            } else {
                RaisedButton(label: "Start sleep timer", glyph: "play.fill", tone: .blue, size: .bar) {
                    timer.start(selected)
                    dismiss()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.margin)
        .padding(.bottom, Spacing.margin)
        // `presentationBackground`, not `.background`: the content is only as wide as it needs to
        // be, so a background painted on it left the sheet's own sides unfilled (owner, 2026-09-12).
        .presentationBackground(palette.sheet)
        // Each presentation carries the app's light/dark itself: an override set back on the pager
        // is applied to a sheet when it opens and not again, so flipping it under an open sheet
        // repainted the page behind and left the sheet as it was.
        .appTheme()
        .environment(\.readerPalette, palette)
        // A shade taller than `.medium` (owner, 2026-09-12: the grid at its new height, and air
        // between it and the key). Medium is a fixed fraction of the screen, and at that height the
        // card all but touched the key; this is the fraction the content actually asks for.
        .presentationDetents([.fraction(0.62)])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}

/// The options as one card: three tiles to a row, the chosen one an ink slab — the `.selected`
/// chip's fill, squared off to a tile.
private struct OptionGrid: View {
    @Environment(\.readerPalette) private var palette
    var options: [SleepOption]
    @Binding var selected: SleepOption

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.grid + 4), count: 3),
                  spacing: Spacing.grid + 4) {
            ForEach(options, id: \.self) { option in
                OptionTile(option: option, isSelected: option == selected) { selected = option }
            }
        }
        .padding(Spacing.grid * 2)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

/// One tile: the number over its unit — "30" over "min", "End" over "of chapter".
private struct OptionTile: View {
    @Environment(\.readerPalette) private var palette
    var option: SleepOption
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(option.tileValue).typeRole(.playerTitle)
                Text(option.tileUnit).typeRole(.meta)
                    .foregroundStyle(isSelected ? palette.page.opacity(0.7) : palette.ink2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(isSelected ? palette.page : palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(isSelected ? palette.ink : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
        .accessibilityLabel(option.chipLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// `chipLabel` split over the tile's two lines. Presentation only, so it lives with the sheet.
private extension SleepOption {
    var tileValue: String {
        switch self {
        case .minutes(let minutes): return "\(minutes)"
        case .endOfChapter: return "End"
        }
    }

    var tileUnit: String {
        switch self {
        case .minutes: return "min"
        case .endOfChapter: return "of chapter"
        }
    }
}
