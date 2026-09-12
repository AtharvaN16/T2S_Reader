import Testing
@testable import T2SCore

@Suite struct RateLimitsTests {
    /// A route that cannot keep up costs the listener a brief catch-up, never a slower voice: the
    /// cap has a floor of 1.0. Time-pitch at half speed smears speech, and the first renders of a
    /// cold engine — the moment a cloud-first reader taps play — measure like a machine that
    /// cannot keep up when it merely has not warmed yet.
    @Test func theCapNeverDropsBelowNormalSpeed() {
        #expect(RateLimits.maxSustainableRate(rtf: 3.0) == 1.0)
        #expect(RateLimits.maxSustainableRate(rtf: 0.9) == 1.0)
        #expect(RateLimits.availableRates(rtf: 3.0) == [0.5, 0.75, 1.0])
    }

    @Test func aRouteWithHeadroomStillEarnsTheFasterRates() {
        #expect(RateLimits.maxSustainableRate(rtf: 0.5) == 1.5)              // 0.5 × 1.5 ≤ 0.8
        #expect(RateLimits.maxSustainableRate(rtf: 0.1) == 4.0)
        #expect(RateLimits.maxSustainableRate(rtf: nil) == 4.0)
    }
}
