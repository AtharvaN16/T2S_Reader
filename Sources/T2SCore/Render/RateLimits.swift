import Foundation

/// Spec §3.6: playback rate multiplies synthesis load. Demand is `RTF × rate`; anything above
/// the safety factor is not offered rather than offered and then stuttering.
public enum RateLimits {
    public static let allRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0]
    public static let safetyFactor = 0.8

    public static func isSustainable(rate: Double, rtf: Double) -> Bool {
        guard rtf.isFinite, rtf > 0 else { return true }
        return rtf * rate <= safetyFactor + 1e-9
    }

    /// The highest listed rate that is sustainable; the lowest listed rate when none is.
    public static func maxSustainableRate(rtf: Double?) -> Double {
        guard let rtf, rtf.isFinite, rtf > 0 else { return allRates.last! }
        return allRates.last(where: { isSustainable(rate: $0, rtf: rtf) }) ?? allRates.first!
    }

    public static func availableRates(rtf: Double?) -> [Double] {
        let cap = maxSustainableRate(rtf: rtf)
        return allRates.filter { $0 <= cap }
    }
}
