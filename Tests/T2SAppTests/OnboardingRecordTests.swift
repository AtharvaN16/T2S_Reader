import Foundation
import Testing
@testable import T2SApp

@Suite struct OnboardingRecordTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "t2s-onboarding-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aFreshInstallHasNotSeenTheWelcome() {
        #expect(!OnboardingRecord.isCompleted(defaults: freshDefaults()))
    }

    @Test func finishingIsRemembered() {
        let defaults = freshDefaults()
        OnboardingRecord.markCompleted(defaults: defaults)
        #expect(OnboardingRecord.isCompleted(defaults: defaults))
    }

    /// Settings' "Show the welcome again": the next launch presents it once more.
    @Test func clearingShowsItAgain() {
        let defaults = freshDefaults()
        OnboardingRecord.markCompleted(defaults: defaults)
        OnboardingRecord.clear(defaults: defaults)
        #expect(!OnboardingRecord.isCompleted(defaults: defaults))
    }
}
