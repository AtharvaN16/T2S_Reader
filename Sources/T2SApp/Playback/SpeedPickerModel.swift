import Foundation
import T2SCore

/// Spec §2.4.5 speed picker: every rate 0.5x–4.0x, unavailable ones (spec §3.6) marked with a footnote.
public struct SpeedPickerModel: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        public var rate: Double
        public var label: String
        public var isAvailable: Bool
        public var isCurrent: Bool

        public var id: Double { rate }

        public init(rate: Double, label: String, isAvailable: Bool, isCurrent: Bool) {
            self.rate = rate
            self.label = label
            self.isAvailable = isAvailable
            self.isCurrent = isCurrent
        }
    }

    public var rows: [Row]
    public var footnote: String?

    public init(rows: [Row], footnote: String?) {
        self.rows = rows
        self.footnote = footnote
    }

    /// 0.5x…4.0x in 0.1x steps (spec §2.4.5), built once so 0.1-step arithmetic never drifts.
    public static let rates: [Double] = (5...40).map { Double($0) / 10 }

    /// `maxRate` is the coordinator's `availableRates.max()` (the highest sustainable rate, spec §3.6).
    public static func make(current: Double, maxRate: Double) -> SpeedPickerModel {
        let rows = rates.map { rate in
            Row(
                rate: rate,
                label: label(for: rate),
                isAvailable: rate <= maxRate + 0.001,
                isCurrent: abs(rate - current) < 0.001
            )
        }
        let highest = rows.filter(\.isAvailable).map(\.rate).max()
        let footnote = rows.contains { !$0.isAvailable }
            ? "Rates above \(label(for: highest ?? 0)) can't be sustained on this device right now."
            : nil
        return SpeedPickerModel(rows: rows, footnote: footnote)
    }

    /// "1x", "1.5x", "0.5x" — one decimal at most, the bare number of spec §2.4.5.
    public static func label(for rate: Double) -> String {
        let rounded = (rate * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))x" : String(format: "%.1fx", rounded)
    }
}
