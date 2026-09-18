import Foundation
import Testing
@testable import T2SApp

@Suite struct GainRampTests {
    @Test func aRampIsAStraightLineInDecibelsThatEndsOnItsTarget() {
        let start = Date(timeIntervalSince1970: 0)
        let ramp = GainRamp(from: -80, to: -24, start: start, duration: 2)
        #expect(ramp.value(at: start) == -80)
        #expect(abs(ramp.value(at: start.addingTimeInterval(1)) - (-52)) < 1e-4)
        #expect(ramp.value(at: start.addingTimeInterval(2)) == -24)
        #expect(ramp.value(at: start.addingTimeInterval(9)) == -24)             // never past
        #expect(!ramp.isDone(at: start.addingTimeInterval(1.9)) && ramp.isDone(at: start.addingTimeInterval(2)))
        #expect(GainRamp(from: -80, to: -24, start: start, duration: 0).value(at: start) == -24)
    }
}
