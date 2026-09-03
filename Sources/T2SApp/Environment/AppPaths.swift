import Foundation

/// Where the library lives on the device: `<Application Support>/t2s` (backed up; the audio cache
/// directory inside it is excluded from backup by `AppEnvironment`).
public enum AppPaths: Sendable {
    public static let appGroupIdentifier = "group.com.t2s.reader"
    public static let audioCapacityKey = "audioCapacityBytes"
    public static let prepareBudgetKey = "prepareBudgetSeconds"
    /// Spec §3.4: the cache cap is user-configurable; 2 GB is roughly 140 hours of 32 kbps AAC.
    public static let defaultAudioCapacityBytes = 2 * 1024 * 1024 * 1024

    /// `base/t2s`, created if needed.
    public static func containerRoot(under base: URL) throws -> URL {
        let root = base.standardizedFileURL.appendingPathComponent("t2s", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// The app's container: `<Application Support>/t2s`.
    public static func defaultContainerRoot() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return try containerRoot(under: support)
    }

    /// The sole shared library root used by the host app and its Share Extension.
    public static func sharedContainerRoot(fileManager: FileManager = .default) throws -> URL {
        guard let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try containerRoot(under: group)
    }
}
