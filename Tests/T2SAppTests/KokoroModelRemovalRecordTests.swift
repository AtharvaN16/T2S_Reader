import Foundation
import Testing
@testable import T2SApp

/// The rule that makes "downloads on launch" and "delete in Settings" agree: a delete switches the
/// automatic download off, and only the download button switches it back on.
@Suite struct KokoroModelRemovalRecordTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "t2s-model-removal-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aFreshInstallDownloadsTheModel() {
        #expect(!KokoroModelRemovalRecord.isSuppressed(defaults: freshDefaults()))
    }

    @Test func aDeleteStopsEveryLaterLaunchFromDownloadingItAgain() {
        let defaults = freshDefaults()
        KokoroModelRemovalRecord.suppress(defaults: defaults)
        #expect(KokoroModelRemovalRecord.isSuppressed(defaults: defaults))
    }

    @Test func theDownloadButtonLetsLaunchesDownloadItAgain() {
        let defaults = freshDefaults()
        KokoroModelRemovalRecord.suppress(defaults: defaults)
        KokoroModelRemovalRecord.allow(defaults: defaults)
        #expect(!KokoroModelRemovalRecord.isSuppressed(defaults: defaults))
    }

    /// The plans go with the model, so the record that says a foreground warm-up built them has to
    /// go too — otherwise a background Prepare pass renders against plans that are not there.
    @Test func aDeleteForgetsThatThisInstallWasWarmed() {
        let defaults = freshDefaults()
        let identity = KokoroWarmUpRecord.identity(bundlePath: "/a", osVersion: "26.6.1", modelsPath: "/m", revision: "3ffe1347")
        KokoroWarmUpRecord.markWarmed(identity: identity, defaults: defaults)
        KokoroWarmUpRecord.clear(defaults: defaults)
        #expect(!KokoroWarmUpRecord.isWarmed(identity: identity, defaults: defaults))
    }
}
