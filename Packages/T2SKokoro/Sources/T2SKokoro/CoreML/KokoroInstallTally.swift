import Foundation

/// One install's download and compile, tallied for the line that says what it cost — the evidence
/// a fresh install leaves in the timing log: how much was fetched and how much copied from a
/// staged twin (the manifest is 619 MB, 238 MB unique), how often a server's refusal was tried
/// again, and what the compile took.
struct KokoroInstallTally: Sendable {
    let startedAt: ContinuousClock.Instant
    private(set) var filesDownloaded = 0
    private(set) var bytesDownloaded = 0
    private(set) var filesCopied = 0
    private(set) var bytesCopied = 0
    private(set) var retries = 0
    private(set) var stagesCompiled = 0
    private(set) var compileSeconds = 0.0

    init(startedAt: ContinuousClock.Instant = .now) {
        self.startedAt = startedAt
    }

    mutating func downloaded(bytes: Int) { filesDownloaded += 1; bytesDownloaded += bytes }
    mutating func copied(bytes: Int) { filesCopied += 1; bytesCopied += bytes }
    mutating func retried() { retries += 1 }
    mutating func compiled(seconds: Double) { stagesCompiled += 1; compileSeconds += seconds }

    func summary(now: ContinuousClock.Instant = .now) -> String {
        let wall = now - startedAt
        let wallSeconds = Double(wall.components.seconds) + Double(wall.components.attoseconds) * 1e-18
        return "kokoro install finished: \(filesDownloaded) files downloaded (\(bytesDownloaded / 1_048_576) MB), "
            + "\(filesCopied) copied from a staged twin (\(bytesCopied / 1_048_576) MB), \(retries) retries, "
            + "\(stagesCompiled) stages compiled in \(String(format: "%.1f", compileSeconds)) s, "
            + "\(String(format: "%.1f", wallSeconds)) s in all"
    }
}
