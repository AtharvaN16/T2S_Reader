import Foundation
import Testing
@testable import T2SKokoro

@Suite struct KokoroCoreMLAvailabilityTests {
    /// The `.xctest` bundle this suite runs from stages none of the Core ML models, so it stands in
    /// for an app whose fetch script was never run.
    private static let bundleWithoutTheStages = Bundle(for: TestBundleMarker.self)

    @Test func aBundleWithoutTheStagesIsUnavailableAndNamesTheFirstMissingOne() {
        #expect(KokoroCoreMLAvailability.check(bundle: Self.bundleWithoutTheStages)
                == .unavailable(.resources(.missing("kokoro_duration_t128"))))
    }

    /// The verdict is resolved in `init`, so the reason is on the model before anyone reads it.
    @Test @MainActor func theModelTurnsThatIntoSomethingToShow() {
        let model = KokoroCoreMLAvailabilityModel(bundle: Self.bundleWithoutTheStages)
        guard case .unavailable(let reason) = model.state else {
            Issue.record("expected the empty bundle to be unavailable, got \(model.state)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(model.verdict == .unavailable(.resources(.missing("kokoro_duration_t128"))))
    }

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func theDevelopmentDirectoryIsAvailableWithTheMeasuredDecision() {
        let verdict = KokoroCoreMLAvailability.check(directory: KokoroCoreMLResources.developmentDirectory)
        guard case .available(let decision, let resources) = verdict else {
            Issue.record("expected the staged files to be available, got \(verdict)")
            return
        }
        // Nothing about the device is asked: the numbers are the A13 measurements, always.
        #expect(decision == KokoroCoreMLDecision.current)
        #expect(resources.voices.count == 28)
    }

    /// Only ever passed to `Bundle(for:)`, to find the `.xctest` bundle this code was loaded from.
    private final class TestBundleMarker {}
}
