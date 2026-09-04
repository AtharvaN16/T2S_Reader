import Foundation
import Testing
@testable import T2SKokoro

@Suite struct KokoroCoreMLDecisionTests {
    @Test func theMeasuredDecisionOffersEveryRate() {
        let d = KokoroCoreMLDecision.current
        #expect(d.measuredRTF == 0.181 && d.maxSustainableRate == 4.0 && d.runtime == "coreml-cpu")
        #expect(d.source.hasSuffix("2026-09-04-pre-a14-runtime.md"))
    }
}
