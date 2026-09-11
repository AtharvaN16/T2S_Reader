import Foundation

/// The timing lines' file on the phone (`Library/Caches/kokoro-timing.log`): every launch appends
/// under a header, so the first launch's stage loads are still there after the second, and a
/// file past ``capBytes`` is moved aside to `.1` first — about a hundred launches — so it never
/// grows without bound. Read with `devicectl device copy from --domain-type appDataContainer`.
enum KokoroTimingLog {
    static let capBytes: UInt64 = 256 * 1024

    /// Opens `path` for appending and writes the launch header. Returns the descriptor, or -1.
    static func open(path: String, capBytes: UInt64 = capBytes, launchedAt: Date = .now,
                     fileManager: FileManager = .default) -> Int32 {
        rotate(path: path, capBytes: capBytes, fileManager: fileManager)
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard descriptor >= 0 else { return descriptor }
        let header = Array((self.header(launchedAt: launchedAt) + "\n").utf8)
        header.withUnsafeBufferPointer { buffer in _ = Darwin.write(descriptor, buffer.baseAddress, buffer.count) }
        return descriptor
    }

    /// `==== launch 2026-09-11 01:20:03 ====`, local time.
    static func header(launchedAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "==== launch \(formatter.string(from: launchedAt)) ===="
    }

    /// Moves a file past the cap to `<path>.1`, replacing the last one moved.
    static func rotate(path: String, capBytes: UInt64, fileManager: FileManager) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let size = attributes[.size] as? UInt64, size > capBytes else { return }
        let aside = path + ".1"
        try? fileManager.removeItem(atPath: aside)
        try? fileManager.moveItem(atPath: path, toPath: aside)
    }
}
