import SwiftUI
import T2SApp

/// Vertical 0.5x–4.0x speed selector. Rates past the coordinator's sustainable threshold are
/// visibly unavailable rather than silently clamped.
struct SpeedPicker: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let model = SpeedPickerModel.make(
            current: env.player.coordinator.rate,
            maxRate: env.player.coordinator.availableRates.max() ?? 4
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Speed")
                    .typeRole(.sectionHeader)
                    .foregroundStyle(Tokens.ink)
                    .padding(.top, Spacing.section)
                    .padding(.bottom, 20)
                ForEach(model.rows) { row in
                    Button {
                        env.player.setRate(row.rate)
                        env.preferences.defaultRate = row.rate
                        dismiss()
                    } label: {
                        HStack {
                            Text(row.label)
                                .typeRole(.rowTitle)
                                .foregroundStyle(row.isAvailable ? Tokens.ink : Tokens.ink3)
                            Spacer()
                            if row.isCurrent {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Tokens.ink)
                            }
                        }
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!row.isAvailable)
                }
                if let footnote = model.footnote {
                    Text(footnote)
                        .typeRole(.meta)
                        .foregroundStyle(Tokens.ink2)
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}
