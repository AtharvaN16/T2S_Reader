import SwiftUI
import T2SApp

/// Sleep-timer sheet with time and chapter-end options (spec §2.4.5).
struct SleepTimerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var selected: SleepOption = .minutes(30)

    var body: some View {
        let timer = env.sleepTimer
        VStack(alignment: .leading, spacing: Spacing.section) {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz").font(.system(size: 17, weight: .semibold))
                Text("Sleep timer").typeRole(.sectionHeader)
            }
            .foregroundStyle(Tokens.ink)
            .padding(.top, Spacing.section)

            if let caption = timer.caption {
                Text(caption).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                Pill(label: "Cancel timer", style: .soft) {
                    timer.cancel()
                    dismiss()
                }
            } else {
                FlowChips(options: SleepOption.all, selected: $selected)
                Pill(label: "Start", glyph: "play.fill", style: .accent) {
                    timer.start(selected)
                    dismiss()
                }
                Text("The timer ends early if the document does.")
                    .typeRole(.meta)
                    .foregroundStyle(Tokens.ink2)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .background(Tokens.raised)
        .presentationDetents([.medium])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}

/// Wrapping row of sleep option chips.
private struct FlowChips: View {
    var options: [SleepOption]
    @Binding var selected: SleepOption

    var body: some View {
        let rows = [Array(options.prefix(3)), Array(options.dropFirst(3))]
        VStack(alignment: .leading, spacing: Spacing.grid) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: Spacing.grid) {
                    ForEach(rows[row], id: \.self) { option in
                        Pill(label: option.chipLabel, style: option == selected ? .selected : .soft) {
                            selected = option
                        }
                    }
                }
            }
        }
    }
}
