import Foundation
import Testing
@testable import T2SApp

@Suite struct KokoroWarmUpRecordTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "t2s-warmup-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aFreshInstallIsNotWarmed() {
        let defaults = freshDefaults()
        let identity = KokoroWarmUpRecord.identity(bundlePath: "/a", osVersion: "26.6.1", modelsPath: "/m", revision: "2e878c6a")
        #expect(!KokoroWarmUpRecord.isWarmed(identity: identity, defaults: defaults))
    }

    @Test func aFinishedForegroundWarmUpIsRemembered() {
        let defaults = freshDefaults()
        let identity = KokoroWarmUpRecord.identity(bundlePath: "/a", osVersion: "26.6.1", modelsPath: "/m", revision: "2e878c6a")
        KokoroWarmUpRecord.markWarmed(identity: identity, defaults: defaults)
        #expect(KokoroWarmUpRecord.isWarmed(identity: identity, defaults: defaults))
    }

    /// A new install, an OS update, a moved model or a new revision each need a foreground warm-up
    /// again: the record is for one identity.
    @Test func anyChangeInTheIdentityNeedsAFreshWarmUp() {
        let defaults = freshDefaults()
        let warmed = KokoroWarmUpRecord.identity(bundlePath: "/a", osVersion: "26.6.1", modelsPath: "/m", revision: "2e878c6a")
        KokoroWarmUpRecord.markWarmed(identity: warmed, defaults: defaults)
        for changed in [
            KokoroWarmUpRecord.identity(bundlePath: "/b", osVersion: "26.6.1", modelsPath: "/m", revision: "2e878c6a"),
            KokoroWarmUpRecord.identity(bundlePath: "/a", osVersion: "26.7", modelsPath: "/m", revision: "2e878c6a"),
            KokoroWarmUpRecord.identity(bundlePath: "/a", osVersion: "26.6.1", modelsPath: "/n", revision: "2e878c6a"),
            KokoroWarmUpRecord.identity(bundlePath: "/a", osVersion: "26.6.1", modelsPath: "/m", revision: "ffffffff"),
        ] {
            #expect(!KokoroWarmUpRecord.isWarmed(identity: changed, defaults: defaults))
        }
    }
}
