import Testing
@testable import T2SCore

@Suite struct RateLimitsTests {
    @Test(arguments: [
        (0.08, 4.0), (0.2, 4.0), (0.3, 2.5), (0.5, 1.5), (0.8, 1.0), (1.0, 0.75), (2.0, 0.5), (9.0, 0.5),
    ])
    func maxRate(rtf: Double, expected: Double) {
        #expect(RateLimits.maxSustainableRate(rtf: rtf) == expected)
    }

    @Test func unknownRTFAllowsEverything() {
        #expect(RateLimits.maxSustainableRate(rtf: nil) == 4.0)
        #expect(RateLimits.maxSustainableRate(rtf: .nan) == 4.0)
        #expect(RateLimits.maxSustainableRate(rtf: 0) == 4.0)
        #expect(RateLimits.availableRates(rtf: nil) == RateLimits.allRates)
    }

    @Test func availableRatesAreAPrefixOfAllRates() {
        #expect(RateLimits.availableRates(rtf: 0.3) == [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5])
        #expect(RateLimits.isSustainable(rate: 2.5, rtf: 0.3))
        #expect(!RateLimits.isSustainable(rate: 3.0, rtf: 0.3))
    }
}
