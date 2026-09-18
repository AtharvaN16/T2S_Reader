import Foundation

/// The sleep sheet's ruler (2026-09-18): every length the finger can land on, and the ones it is
/// drawn taller and named. Pure, so the bar's arithmetic is tested without a view.
///
/// Five-minute stops from five minutes to two hours. Five is fine enough that "a little longer"
/// is a stop of its own rather than a jump to the next chip, and twenty-four stops leave each
/// tick about a finger-width apart at phone width, which is what makes the bar draggable rather
/// than merely tappable. The old chips — 10, 20, 30, 45, 60 — stay on the bar as landmarks, with
/// 90 and 120 joining them because the bar reaches that far now.
public enum SleepDial {
    public static let step = 5
    public static let range = 5...120
    /// Every minute value the ruler can rest on, in order.
    public static let stops: [Int] = Array(stride(from: range.lowerBound, through: range.upperBound, by: step))
    /// The stops drawn taller and named, so the common answers can be hit without reading the number.
    public static let landmarks: [Int] = [10, 20, 30, 45, 60, 90, 120]
    /// Where the sheet opens the first time (spec §2.4.5's middle chip).
    public static let defaultMinutes = 30

    /// The stop nearest `minutes`, inside the range.
    public static func snapped(_ minutes: Int) -> Int {
        let clamped = min(range.upperBound, max(range.lowerBound, minutes))
        let index = (Double(clamped - range.lowerBound) / Double(step)).rounded()
        return range.lowerBound + Int(index) * step
    }

    /// The stop under a finger at `fraction` of the bar's width: 0 at the left end, 1 at the right.
    public static func minutes(atFraction fraction: Double) -> Int {
        let f = min(1, max(0, fraction.isNaN ? 0 : fraction))
        let index = Int((f * Double(stops.count - 1)).rounded())
        return stops[index]
    }

    /// Where a stop sits along the bar, 0…1. An off-stop value is placed where it would snap to.
    public static func fraction(of minutes: Int) -> Double {
        Double(snapped(minutes) - range.lowerBound) / Double(range.upperBound - range.lowerBound)
    }
}
