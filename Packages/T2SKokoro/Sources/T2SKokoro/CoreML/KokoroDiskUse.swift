import Foundation

/// Measuring and removing a directory of ours, in the one place both callers can reach: the model
/// install (``KokoroCoreMLInstall``) and Core ML's compute-plan cache (``KokoroPlanCache``) are what
/// the on-device voice costs a phone, and Settings → Storage shows and reclaims the two together.
public enum KokoroDiskUse {
    /// The bytes of every regular file under `directory`; 0 when there is none.
    public static func size(of directory: URL, fileManager: FileManager = .default) -> Int64 {
        guard let files = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                 options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// Removes `directory` and reports the bytes it held; 0 when there was none. A removal that
    /// fails part-way reports what did go, so a caller's number is never larger than the truth.
    @discardableResult
    public static func remove(_ directory: URL, fileManager: FileManager = .default) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else { return 0 }
        let before = size(of: directory, fileManager: fileManager)
        do {
            try fileManager.removeItem(at: directory)
            return before
        } catch {
            return before - size(of: directory, fileManager: fileManager)
        }
    }
}
