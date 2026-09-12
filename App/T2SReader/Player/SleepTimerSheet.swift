import SwiftUI
import T2SApp

/// Sleep-timer sheet with time and chapter-end options (spec §2.4.5).
///
/// The owner's reference (2026-09-12) is a centred sheet: the moon over its own title, the options
/// as a grid of tiles inside one grey card rather than a wrapping row of chips, and one full-width
/// key under it. Our own elements do the work — `Tokens`, the `.selected` chip's ink fill, `Pill`
/// — so it is the podcast app's *shape*, not its paint.
struct SleepTimerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var selected: SleepOption = .minutes(30)

    var body: some View {
        let timer = env.sleepTimer
        VStack(spacing: Spacing.row - 4) {
            VStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Tokens.ink3)
                Text("Sleep timer").typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
            }
            .padding(.top, Spacing.margin)

            if let caption = timer.caption {
                Text(caption).typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                Pill(label: "Cancel timer", style: .soft, fillsWidth: true) {
                    timer.cancel()
                    dismiss()
                }
            } else {
                OptionGrid(options: SleepOption.all, selected: $selected)
                VStack(spacing: 12) {
                    Pill(label: "Start sleep timer", glyph: "play.fill", style: .accent, fillsWidth: true) {
                        timer.start(selected)
                        dismiss()
                    }
                    Text("The timer ends early if the document does.")
                        .typeRole(.meta)
                        .foregroundStyle(Tokens.ink2)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.margin)
        // `presentationBackground`, not `.background`: the content is only as wide as it needs to
        // be, so a background painted on it left the sheet's own sides unfilled (owner, 2026-09-12).
        .presentationBackground(Tokens.raised)
        .presentationDetents([.medium])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}

/// The options as one card: three tiles to a row, the chosen one an ink slab — the `.selected`
/// chip's fill, squared off to a tile.
private struct OptionGrid: View {
    var options: [SleepOption]
    @Binding var selected: SleepOption

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.grid), count: 3),
                  spacing: Spacing.grid) {
            ForEach(options, id: \.self) { option in
                OptionTile(option: option, isSelected: option == selected) { selected = option }
            }
        }
        .padding(Spacing.grid)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// One tile: the number over its unit — "30" over "min", "End" over "of chapter".
private struct OptionTile: View {
    var option: SleepOption
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(option.tileValue).typeRole(.playerTitle)
                Text(option.tileUnit).typeRole(.meta)
                    .foregroundStyle(isSelected ? Tokens.ground.opacity(0.7) : Tokens.ink2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(isSelected ? Tokens.ground : Tokens.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(isSelected ? Tokens.ink : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
