import CoreML
import Foundation
import os

/// Installs the Core ML Kokoro model on the device: downloads the 72 files of
/// ``KokoroCoreMLManifest`` into a staging directory, verifies each against its SHA-256, compiles
/// every `.mlpackage` into a `.mlmodelc`, and leaves the compiled layout ``KokoroCoreMLResources``
/// locates with `locate(installedIn:)`.
///
/// The model is no longer in the app bundle (2026-09-10): 676 MB per install was every Xcode run's
/// wait, and the models sit here at a path that survives reinstalls — under
/// `Application Support/KokoroCoreML/<revision prefix>/`, excluded from backup.
///
/// Every step is idempotent and resumable: a file already there at its hash is skipped, a `.part`
/// is what a download writes until it is verified, a stage already compiled is skipped and its
/// source removed. Cancellation between files leaves nothing half-written. Downloads go over
/// Wi-Fi only (`allowsExpensiveNetworkAccess` off) and wait for it; compiles wait on `admission`
/// — the app's foreground gate — because `coremlc` on a phone is CPU the background is not allowed.
public actor KokoroCoreMLInstall {
    /// What the installer is doing, for the veil.
    public enum Progress: Hashable, Sendable {
        /// Waiting for a network the download is allowed on (Wi-Fi).
        case waitingForNetwork(totalBytes: Int)
        case downloading(bytes: Int, totalBytes: Int)
        /// A file's download was refused or dropped and will be tried again after `after` seconds
        /// (`attempt` is the one about to be made).
        case retrying(path: String, attempt: Int, after: TimeInterval)
        case compiling(stage: Int, totalStages: Int)
    }

    public enum Failure: Error, Hashable, Sendable, LocalizedError {
        /// `status` is the HTTP status the server answered with, when it answered at all.
        case download(String, status: Int?)
        case checksumMismatch(String)
        case compile(String)

        public var errorDescription: String? {
            switch self {
            case .download(let path, let status):
                status.map { "The voice could not be downloaded (\(path), HTTP \($0))." }
                    ?? "The voice could not be downloaded (\(path))."
            case .checksumMismatch(let path): "A downloaded voice file was damaged (\(path))."
            case .compile(let stage): "The voice could not be prepared (\(stage))."
            }
        }
    }

    /// A response outside 200–299, with the server's `Retry-After` when it sent one in seconds.
    public struct HTTPStatusError: Error, Hashable, Sendable {
        public let status: Int
        public let retryAfter: TimeInterval?
        public init(status: Int, retryAfter: TimeInterval? = nil) {
            self.status = status
            self.retryAfter = retryAfter
        }
    }

    /// Fetches `url` into `destination` (creating or replacing it), reporting bytes as they land.
    /// The default is a Wi-Fi-only `URLSession`; tests inject a fake.
    public typealias Downloader = @Sendable (_ url: URL, _ destination: URL,
                                            _ onBytes: @escaping @Sendable (_ bytes: Int) -> Void,
                                            _ onWaiting: @escaping @Sendable () -> Void) async throws -> Void
    /// Compiles a `.mlpackage` and returns the `.mlmodelc` it produced (somewhere temporary).
    public typealias Compiler = @Sendable (_ package: URL) async throws -> URL
    /// Waits between download attempts; tests inject one that only records.
    public typealias Sleeper = @Sendable (_ seconds: TimeInterval) async -> Void

    private let root: URL
    private let manifest: [KokoroCoreMLManifest.File]
    private let downloader: Downloader
    private let compiler: Compiler
    private let sleeper: Sleeper
    private let admission: (@Sendable () async -> Void)?
    /// A file is asked for this many times before the install gives up on it.
    public static let maximumAttempts = 5
    /// The wait before attempt n+1 when the server named none: 2, 4, 8, 16 s.
    static func backoff(afterAttempt attempt: Int) -> TimeInterval { min(60, pow(2, Double(attempt))) }
    private static let log = Logger(subsystem: "com.t2s.reader", category: "kokoro.install")

    /// `root` is the revision directory, e.g. `…/KokoroCoreML/2e878c6a`. `admission` is awaited
    /// before each compile.
    public init(root: URL,
                manifest: [KokoroCoreMLManifest.File] = KokoroCoreMLManifest.files,
                downloader: @escaping Downloader = KokoroCoreMLInstall.wifiDownloader,
                compiler: @escaping Compiler = { try await MLModel.compileModel(at: $0) },
                sleeper: @escaping Sleeper = { seconds in try? await Task.sleep(for: .seconds(seconds)) },
                admission: (@Sendable () async -> Void)? = nil) {
        self.root = root
        self.manifest = manifest
        self.downloader = downloader
        self.compiler = compiler
        self.sleeper = sleeper
        self.admission = admission
    }

    /// The revision directory under the app's Application Support: `KokoroCoreML/<revision prefix>`.
    public static func defaultRoot(applicationSupport: URL) -> URL {
        applicationSupport
            .appending(path: "KokoroCoreML", directoryHint: .isDirectory)
            .appending(path: KokoroCoreMLResources.revisionPrefix, directoryHint: .isDirectory)
    }

    /// Where the sources are staged (`coreml/`, `voices/`, `runtime/`) and the compiled stages go.
    var stagingDirectory: URL { root.appending(path: "staging", directoryHint: .isDirectory) }
    var compiledDirectory: URL { root.appending(path: "compiled", directoryHint: .isDirectory) }

    /// Downloads what is missing, compiles what is not compiled, and returns the installed layout.
    public func install(progress: @escaping @Sendable (Progress) -> Void) async throws -> KokoroCoreMLResources.Located {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: compiledDirectory, withIntermediateDirectories: true)
        try Self.excludeFromBackup(root)

        try await downloadMissingFiles(progress: progress)
        try await compileMissingStages(progress: progress)
        try removeCompiledSources()

        switch KokoroCoreMLResources.locate(installedIn: root) {
        case .success(let located): return located
        case .failure(let failure): throw Failure.compile(failure.errorDescription ?? "\(failure)")
        }
    }

    // MARK: Download

    private func downloadMissingFiles(progress: @escaping @Sendable (Progress) -> Void) async throws {
        let total = manifest.reduce(0) { $0 + $1.byteCount }
        var done = 0
        // Everything already verified counts as done from the start, so a resumed install's bar
        // begins where the last one stopped.
        var pending: [KokoroCoreMLManifest.File] = []
        for file in manifest {
            let destination = stagingDirectory.appending(path: file.path)
            let compiledStage = compiledStageURL(forSource: file.path)
            if let compiledStage, FileManager.default.fileExists(atPath: compiledStage.path(percentEncoded: false)) {
                done += file.byteCount                                // its stage is compiled; the source is gone or going
            } else if try Self.matches(destination, file) {
                done += file.byteCount
            } else {
                pending.append(file)
            }
        }
        guard !pending.isEmpty else { return }
        progress(.downloading(bytes: done, totalBytes: total))

        for file in pending {
            try Task.checkCancellation()
            let destination = stagingDirectory.appending(path: file.path)
            let part = destination.appendingPathExtension("part")
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: part)
            let base = done
            // A stage's bucket variants share their weights — the manifest lists 619 MB of which
            // 238 MB is unique — so a file whose bytes are already staged under another path is
            // copied from there, not fetched again.
            if let twin = stagedTwin(of: file) {
                Self.log.notice("copying \(file.path, privacy: .public) from \(twin.lastPathComponent, privacy: .public)")
                try FileManager.default.copyItem(at: twin, to: part)
            } else {
                Self.log.notice("downloading \(file.path, privacy: .public) (\(file.byteCount, privacy: .public) bytes)")
                // A refusal the server may lift (429, a 5xx, a dropped connection) is tried again after
                // a wait — the server's own `Retry-After`, else doubling from two seconds — up to
                // `maximumAttempts`; anything else (a 404, a checksum) fails the install at once. The
                // `.part` is removed before every attempt: the download has no `Range`, so it restarts.
                var attempt = 0
                while true {
                    attempt += 1
                    try? FileManager.default.removeItem(at: part)
                    let counter = OSAllocatedUnfairLock(initialState: 0)
                    do {
                        try await downloader(file.url, part, { bytes in
                            let sum = counter.withLock { $0 += bytes; return $0 }
                            progress(.downloading(bytes: base + min(sum, file.byteCount), totalBytes: total))
                        }, {
                            progress(.waitingForNetwork(totalBytes: total))
                        })
                        break
                    } catch is CancellationError {
                        try? FileManager.default.removeItem(at: part)
                        throw CancellationError()
                    } catch {
                        try? FileManager.default.removeItem(at: part)
                        let status = (error as? HTTPStatusError)?.status
                        Self.log.error("download failed for \(file.path, privacy: .public) (attempt \(attempt, privacy: .public)): \(String(describing: error), privacy: .public)")
                        guard Self.isRetryable(error), attempt < Self.maximumAttempts else {
                            throw Failure.download(file.path, status: status)
                        }
                        let delay = (error as? HTTPStatusError)?.retryAfter ?? Self.backoff(afterAttempt: attempt)
                        progress(.retrying(path: file.path, attempt: attempt + 1, after: delay))
                        await sleeper(delay)
                        try Task.checkCancellation()
                    }
                }
            }
            guard try Self.matches(part, file) else {
                try? FileManager.default.removeItem(at: part)
                Self.log.error("checksum mismatch for \(file.path, privacy: .public)")
                throw Failure.checksumMismatch(file.path)
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: part, to: destination)
            done += file.byteCount
            progress(.downloading(bytes: done, totalBytes: total))
        }
    }

    /// A staged file of another path with `file`'s content, verified, if there is one — the
    /// stage's other bucket variants, or nothing once a variant's stage has been compiled and its
    /// source removed.
    private func stagedTwin(of file: KokoroCoreMLManifest.File) -> URL? {
        for candidate in manifest where candidate.sha256 == file.sha256 && candidate.path != file.path {
            let url = stagingDirectory.appending(path: candidate.path)
            if (try? Self.matches(url, candidate)) == true { return url }
        }
        return nil
    }

    /// Whether a download failure is the passing kind: the server asking for a pause (429), a
    /// request it timed out (408), a server-side error (5xx), or a connection that timed out or
    /// dropped. A 404 or 403 is not — the file is not going to appear.
    static func isRetryable(_ error: Error) -> Bool {
        if let http = error as? HTTPStatusError {
            return http.status == 429 || http.status == 408 || (500 ... 599).contains(http.status)
        }
        if let urlError = error as? URLError {
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(urlError.code)
        }
        return false
    }

    /// Whether `url` is a regular file of the manifest's size whose SHA-256 matches.
    static func matches(_ url: URL, _ file: KokoroCoreMLManifest.File) throws -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              attributes[.type] as? FileAttributeType == .typeRegular,
              attributes[.size] as? Int == file.byteCount
        else { return false }
        return try KokoroResources.sha256Hex(of: url) == file.sha256
    }

    // MARK: Compile

    /// The stages the manifest carries, in load order, each with its staged `.mlpackage` and its
    /// compiled `.mlmodelc`. The shipped manifest carries every stage; a test's may not.
    private var stages: [(name: String, package: URL, compiled: URL)] {
        let carried = Set(manifest.compactMap { file -> String? in
            guard file.path.hasPrefix("coreml/"), let package = file.path.split(separator: "/").dropFirst().first,
                  package.hasSuffix(".mlpackage") else { return nil }
            return String(package.dropLast(".mlpackage".count))
        })
        return KokoroCoreMLResources.stageNames().filter { carried.contains($0) }.map { name in
            (name,
             stagingDirectory.appending(path: "coreml/\(name).mlpackage", directoryHint: .isDirectory),
             compiledDirectory.appending(path: "\(name).mlmodelc", directoryHint: .isDirectory))
        }
    }

    /// The compiled stage a staged source file belongs to, or nil for a voice or a runtime file.
    private func compiledStageURL(forSource path: String) -> URL? {
        guard path.hasPrefix("coreml/"), let package = path.split(separator: "/").dropFirst().first,
              package.hasSuffix(".mlpackage") else { return nil }
        let name = String(package.dropLast(".mlpackage".count))
        return compiledDirectory.appending(path: "\(name).mlmodelc", directoryHint: .isDirectory)
    }

    private func compileMissingStages(progress: @escaping @Sendable (Progress) -> Void) async throws {
        let all = stages
        let pending = all.filter { !FileManager.default.fileExists(atPath: $0.compiled.path(percentEncoded: false)) }
        guard !pending.isEmpty else { return }
        var compiledCount = all.count - pending.count
        progress(.compiling(stage: compiledCount, totalStages: all.count))
        for stage in pending {
            try Task.checkCancellation()
            await admission?()
            try Task.checkCancellation()
            let clock = ContinuousClock()
            let started = clock.now
            let produced: URL
            do {
                produced = try await compiler(stage.package)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.log.error("compile failed for \(stage.name, privacy: .public): \(String(describing: error), privacy: .public)")
                throw Failure.compile(stage.name)
            }
            // Into place atomically: a half-moved directory would read as "compiled" next time.
            let temporary = compiledDirectory.appending(path: "\(stage.name).mlmodelc.moving", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: temporary)
            try FileManager.default.moveItem(at: produced, to: temporary)
            try? FileManager.default.removeItem(at: stage.compiled)
            try FileManager.default.moveItem(at: temporary, to: stage.compiled)
            compiledCount += 1
            let elapsed = clock.now - started
            Self.log.notice("compiled \(stage.name, privacy: .public) in \(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18, format: .fixed(precision: 1), privacy: .public) s (\(compiledCount, privacy: .public)/\(all.count, privacy: .public))")
            progress(.compiling(stage: compiledCount, totalStages: all.count))
        }
    }

    /// The `.mlpackage` sources of compiled stages are 590 MB the compiled layout duplicates; gone
    /// once their stage is in place. Voices and runtime files stay: the layout reads them in place.
    private func removeCompiledSources() throws {
        for stage in stages where FileManager.default.fileExists(atPath: stage.compiled.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: stage.package)
        }
    }

    private static func excludeFromBackup(_ directory: URL) throws {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    // MARK: The network

    /// A `URLSession` that only downloads over Wi-Fi (no expensive or constrained paths) and waits
    /// for one rather than fail, streaming each file to disk as it arrives.
    public static let wifiDownloader: Downloader = { url, destination, onBytes, onWaiting in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 6 * 3600
        let delegate = ConnectivityDelegate(onWaiting: onWaiting)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200 ... 299).contains(http.statusCode) else {
            throw HTTPStatusError(status: http.statusCode,
                                  retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        }
        FileManager.default.createFile(atPath: destination.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                onBytes(buffer.count)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            onBytes(buffer.count)
        }
    }

    private final class ConnectivityDelegate: NSObject, URLSessionTaskDelegate {
        private let onWaiting: @Sendable () -> Void
        init(onWaiting: @escaping @Sendable () -> Void) { self.onWaiting = onWaiting }
        func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) { onWaiting() }
    }
}
