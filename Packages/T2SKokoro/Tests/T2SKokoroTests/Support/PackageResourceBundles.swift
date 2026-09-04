import Foundation
import T2SKokoro

/// The two things every test that touches the real model needs before it starts.
enum KokoroTestSupport {
    /// Whether `scripts/fetch-kokoro-model.sh` has installed the weights and the voice table on this
    /// machine. CI has neither, so the tests that need them are `.enabled(if:)` this.
    static let haveRealFiles = (try? KokoroResources.locate(in: KokoroResources.developmentDirectory).get()) != nil

    /// Whether `scripts/fetch-kokoro-coreml.sh --app` has staged the Core ML model files on this
    /// machine. CI has none, so the tests that need them are `.enabled(if:)` this.
    static let haveCoreMLFiles =
        (try? KokoroCoreMLResources.locate(inDirectory: KokoroCoreMLResources.developmentDirectory).get()) != nil

    /// Points KokoroSwift's `Bundle.module` at this test bundle's resources. Call it at the top of
    /// every test that builds an engine or a probe over the real files.
    ///
    /// KokoroSwift, MisakiSwift and mlx-swift each ship a SwiftPM resource bundle (the lexicons, the
    /// Metal library). Xcode stages all of them in this `.xctest` bundle's `Resources`, but the
    /// `Bundle.module` accessor generated inside a package *framework* only looks in `Bundle.main` —
    /// the `xctest` tool — and in the framework's own `Resources`, and traps with
    /// "unable to find bundle named KokoroSwift_KokoroSwift" when it finds neither.
    /// `PACKAGE_RESOURCE_BUNDLE_PATH` is the override SwiftPM generates for exactly this case, and
    /// `xcodebuild` forwards no environment of its own to the test process, so it is set here.
    ///
    /// It is an explicit call rather than a lazily evaluated `static let` because `setenv` mutates
    /// the process environment: writing it at an unpredictable moment can race another test's
    /// `ProcessInfo.environment` read — `KokoroResources.developmentDirectory` does one on every
    /// call. The lock makes the write happen exactly once, but once is still one write, so what
    /// actually closes the race is that nothing else is running: `scripts/test-kokoro.sh` passes
    /// `-parallel-testing-enabled NO`. `.serialized` on a suite is not enough on its own — it orders
    /// tests within one suite and leaves suites running beside each other.
    ///
    /// The app needs none of this: linked into an app the bundles are in `Bundle.main.resourceURL`,
    /// which is the accessor's first candidate.
    static func locatePackageResourceBundles() {
        lock.lock()
        defer { lock.unlock() }
        guard !haveLocatedPackageResourceBundles else { return }
        haveLocatedPackageResourceBundles = true
        guard ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] == nil,
              let resources = Bundle(for: TestBundleFinder.self).resourceURL
        else { return }
        setenv("PACKAGE_RESOURCE_BUNDLE_PATH", resources.path(percentEncoded: false), 1)
    }

    /// Only ever passed to `Bundle(for:)`, to find the `.xctest` bundle this code was loaded from.
    private final class TestBundleFinder {}

    private static let lock = NSLock()
    /// Guarded by ``lock``.
    private nonisolated(unsafe) static var haveLocatedPackageResourceBundles = false
}
