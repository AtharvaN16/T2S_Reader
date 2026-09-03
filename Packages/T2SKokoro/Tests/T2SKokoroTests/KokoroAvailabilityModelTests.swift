import Foundation
import Synchronization
import Testing
@testable import T2SKokoro

@Suite @MainActor struct KokoroAvailabilityModelTests {
    @Test func startsCheckingAndSettlesOnTheVerdict() async {
        let model = KokoroAvailabilityModel(probe: KokoroAvailability.Probe(
            isSimulator: true,
            supportsRequiredGPUFamily: { true },
            resourcesDirectory: nil,
            decision: nil
        ))
        #expect(model.state == .checking)
        #expect(model.isAvailable == false)

        let verdict = await model.resolve()
        #expect(verdict == .unavailable(.simulator))
        #expect(model.state == .unavailable(.simulator))
        #expect(model.isAvailable == false)
    }

    /// One probe per launch: the composition root, the voice list and the route fallback all ask, and
    /// only the first ask does the work.
    @Test func concurrentCallersShareOneProbe() async {
        let calls = Mutex(0)
        let model = KokoroAvailabilityModel(probe: KokoroAvailability.Probe(
            isSimulator: false,
            supportsRequiredGPUFamily: {
                calls.withLock { $0 += 1 }
                return true
            },
            resourcesDirectory: nil,
            decision: nil
        ))

        async let first = model.resolve()
        async let second = model.resolve()
        let verdicts = await [first, second]

        #expect(verdicts == [.unavailable(.noRuntimeDecision), .unavailable(.noRuntimeDecision)])
        #expect(calls.withLock { $0 } == 1)
        #expect(model.state == .unavailable(.noRuntimeDecision))
    }
}
