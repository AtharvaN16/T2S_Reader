import Foundation

/// Whether a foreground warm-up has built the Core ML compute plans on this install.
///
/// A plan build is a minute of a core per stage on a first launch, and iOS kills a process that is
/// not frontmost for exactly that (the iPhone 17 Pro, 2026-09-09 15:14). The launch warm-up waits
/// on the foreground gate, so it never builds plans in the background; a *background* Prepare pass
/// cannot wait for a foreground, so it asks here first and skips until a foreground warm-up has
/// finished on this install. The identity the record is keyed on changes with anything that could
/// invalidate Core ML's plan cache — the bundle's path (a new install), the OS build, the model
/// revision and where the models live — so after any of those the next warm-up is a foreground one.
public enum KokoroWarmUpRecord {
    public static let key = "kokoro.warmedInstall"

    public static func identity(bundlePath: String, osVersion: String, modelsPath: String, revision: String) -> String {
        [bundlePath, osVersion, modelsPath, revision].joined(separator: "|")
    }

    public static func isWarmed(identity: String, defaults: UserDefaults) -> Bool {
        defaults.string(forKey: key) == identity
    }

    public static func markWarmed(identity: String, defaults: UserDefaults) {
        defaults.set(identity, forKey: key)
    }

    /// Forgets the record, so the next warm-up is a foreground one again. What a delete of the
    /// model from Settings → Storage leaves behind otherwise is a record claiming plans that were
    /// removed with it, and a background Prepare pass that renders against nothing.
    public static func clear(defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}
