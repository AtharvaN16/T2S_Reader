import Foundation

/// Core ML's compiled compute plans, where iOS keeps them: `Library/Caches/<bundle id>/
/// com.apple.e5rt.e5bundlecache`, inside the app's own container.
///
/// iOS keys a plan on the install, so every install — a build from the Mac, an App Store update —
/// warms a fresh generation, about a gigabyte on the CPU path, and nothing removes the one before:
/// the iPhone 11 Pro held 4.36 GB across a day of builds (2026-09-10, 211 entries), the phone
/// filled, and the next warm-up's BNNS compile failed with "No space left on device" inside that
/// very directory (2026-09-11 00:57). The launch composition calls ``prepare(for:cachesDirectory:
/// bundleIdentifier:defaults:fileManager:)`` before anything can load a stage: a cache built for
/// another warm-up identity (`KokoroWarmUpRecord.identity`), or for none on record, is wiped, so
/// the cache holds one generation — this install's.
public enum KokoroPlanCache {
    /// The warm-up identity the cache on disk was built for.
    public static let identityKey = "kokoro.planCache.identity"
    /// iOS's name for the directory, under the bundle identifier's directory in Caches.
    public static let directoryName = "com.apple.e5rt.e5bundlecache"

    /// Where iOS keeps the app's compute plans.
    public static func directory(cachesDirectory: URL, bundleIdentifier: String) -> URL {
        cachesDirectory.appending(path: bundleIdentifier).appending(path: directoryName)
    }

    /// Wipes the plan cache when it was built for another identity — or for none on record, which
    /// is every install that warmed before this record existed — and records `identity` as the
    /// owner of whatever is built next. Returns the bytes removed, or nil when the cache is this
    /// identity's own and was kept.
    @discardableResult
    public static func prepare(
        for identity: String,
        cachesDirectory: URL,
        bundleIdentifier: String,
        defaults: UserDefaults,
        fileManager: FileManager = .default
    ) -> Int64? {
        guard defaults.string(forKey: identityKey) != identity else { return nil }
        let removed = wipe(directory(cachesDirectory: cachesDirectory, bundleIdentifier: bundleIdentifier), fileManager: fileManager)
        defaults.set(identity, forKey: identityKey)
        return removed
    }

    /// Removes the plan cache directory and reports the bytes it held; 0 when there was none. A
    /// removal that fails part-way reports what did go.
    @discardableResult
    public static func wipe(_ directory: URL, fileManager: FileManager = .default) -> Int64 {
        KokoroDiskUse.remove(directory, fileManager: fileManager)
    }

    /// The bytes of every regular file under `directory`.
    public static func size(of directory: URL, fileManager: FileManager = .default) -> Int64 {
        KokoroDiskUse.size(of: directory, fileManager: fileManager)
    }
}
