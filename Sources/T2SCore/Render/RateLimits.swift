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

    /// The highest listed rate that is sustainable, and never below 1.0: a route that cannot keep
    /// up costs the listener a brief catch-up, not a slower voice. Time-pitch at half speed smears
    /// speech, and the first renders of an engine that has not warmed yet — the moment a
    /// cloud-first reader taps play — measure exactly like a machine that cannot keep up.
    public static func maxSustainableRate(rtf: Double?) -> Double {
        guard let rtf, rtf.isFinite, rtf > 0 else { return allRates.last! }
        return max(1.0, allRates.last(where: { isSustainable(rate: $0, rtf: rtf) }) ?? 1.0)
    }

    public static func availableRates(rtf: Double?) -> [Double] {
        let cap = maxSustainableRate(rtf: rtf)
        return allRates.filter { $0 <= cap }
    }
}
