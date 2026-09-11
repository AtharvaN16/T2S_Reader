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
/// is what a download writes until it is verified — and what the next attempt, or the next
/// launch, asks the server to continue (`Range`) — a stage already compiled is skipped and its
/// source removed. Cancellation leaves at most a `.part` the next install resumes. Downloads go
/// over Wi-Fi only (`allowsExpensiveNetworkAccess` off), through one `URLSession` per install,
/// and wait for it; compiles wait on `admission` — the app's foreground gate — because `coremlc`
/// on a phone is CPU the background is not allowed.
public actor KokoroCoreMLInstall {
    /// What the installer is doing, for the veil.
    public enum Progress: Hashable, Sendable {
        /// Waiting for a network the download is allowed on (Wi-Fi).
        case waitingForNetwork(totalBytes: Int)
        case downloading(bytes: Int, totalBytes: Int)
        /// A file's download was refused or dropped and will be tried again after `after` seconds
        /// — what the server asked for, held to `maximumServerWait`, else the backoff (`attempt`
        /// is the one about to be made).
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

    /// A response outside 200–299, with how long the server asked the client to wait, when it said.
    public struct HTTPStatusError: Error, Hashable, Sendable {
        public let status: Int
        /// Seconds to wait before asking again, from the most specific header that names one:
        /// `Retry-After` (seconds or an HTTP-date), then `RateLimit-Reset` / `X-RateLimit-Reset`
        /// (seconds until the window resets, or the epoch second it resets at), then the `t=` of the
        /// IETF-draft `RateLimit` field Hugging Face puts on every 429 — `ratelimit:
        /// "resolvers";r=2998;t=217` against the model's repository on 2026-09-10.
        public let retryAfter: TimeInterval?
        /// The rate-limit headers as the server sent them, for the timing log: a spent quota
        /// (`r=0`) reads differently from an IP blocklist, and the phone's 429s have not said which.
        public let rateLimit: String?

        public init(status: Int, retryAfter: TimeInterval? = nil, rateLimit: String? = nil) {
            self.status = status
            self.retryAfter = retryAfter
            self.rateLimit = rateLimit
        }

        /// The error for `response`, its wait read from the headers.
        init(_ response: HTTPURLResponse, now: Date = .now) {
            self.init(status: response.statusCode,
                      retryAfter: Self.wait(in: response, now: now),
                      rateLimit: Self.rateLimitHeaders(of: response))
        }

        static let rateLimitHeaderNames = ["Retry-After", "RateLimit", "RateLimit-Policy", "RateLimit-Reset", "X-RateLimit-Reset"]

        /// The first header, most specific first, that names a wait still ahead; a date already
        /// passed says nothing.
        static func wait(in response: HTTPURLResponse, now: Date) -> TimeInterval? {
            func header(_ name: String) -> String? {
                response.value(forHTTPHeaderField: name)?.trimmingCharacters(in: .whitespaces)
            }
            let waits: [TimeInterval?] = [
                header("Retry-After").flatMap { text in TimeInterval(text) ?? httpDate(text).map { $0.timeIntervalSince(now) } },
                header("RateLimit-Reset").flatMap(TimeInterval.init).map { untilReset($0, now: now) },
                header("X-RateLimit-Reset").flatMap(TimeInterval.init).map { untilReset($0, now: now) },
                header("RateLimit").flatMap(resetParameter(of:)).map { untilReset($0, now: now) },
            ]
            return waits.compactMap { $0 }.first { $0 > 0 }
        }

        /// A reset a year or more away is not a wait but a clock: the epoch second the window resets at.
        static func untilReset(_ value: TimeInterval, now: Date) -> TimeInterval {
            value > 365 * 86_400 ? value - now.timeIntervalSince1970 : value
        }

        /// The `t=<seconds>` of a `RateLimit` field (`"resolvers";r=2998;t=217`), the first policy's.
        static func resetParameter(of field: String) -> TimeInterval? {
            for parameter in field.split(whereSeparator: { $0 == ";" || $0 == "," }) {
                let trimmed = parameter.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("t=") { return TimeInterval(trimmed.dropFirst(2)) }
            }
            return nil
        }

        /// RFC 9110's IMF-fixdate, the form a `Retry-After` date takes: `Sun, 06 Nov 1994 08:49:37 GMT`.
        static func httpDate(_ text: String) -> Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            return formatter.date(from: text)
        }

        /// `name: value` for each rate-limit header present, or nil when there is none.
        static func rateLimitHeaders(of response: HTTPURLResponse) -> String? {
            let present = rateLimitHeaderNames.compactMap { name in
                response.value(forHTTPHeaderField: name).map { "\(name.lowercased()): \($0)" }
            }
            return present.isEmpty ? nil : present.joined(separator: ", ")
        }
    }

    /// Fetches `url` into `destination`, reporting how many bytes the file holds as they land. When
    /// `destination` already holds the head of the file — an earlier attempt's, or an earlier
    /// launch's — the fetch asks for the rest and appends it, or replaces the file when the server
    /// answers with the whole of it. Tests inject a fake.
    public typealias Downloader = @Sendable (_ url: URL, _ destination: URL,
                                            _ onBytes: @escaping @Sendable (_ bytes: Int) -> Void,
                                            _ onWaiting: @escaping @Sendable () -> Void) async throws -> Void

    /// The network of one install: `download` fetches each file, and `close` is called once when
    /// the downloads are done, however they end. `wifi()` is the live one; tests inject a fake with
    /// nothing to close.
    public struct Session: Sendable {
        public let download: Downloader
        public let close: @Sendable () -> Void

        public init(download: @escaping Downloader, close: @escaping @Sendable () -> Void = {}) {
            self.download = download
            self.close = close
        }
    }

    /// Compiles a `.mlpackage` and returns the `.mlmodelc` it produced (somewhere temporary).
    public typealias Compiler = @Sendable (_ package: URL) async throws -> URL
    /// Waits between download attempts; tests inject one that only records.
    public typealias Sleeper = @Sendable (_ seconds: TimeInterval) async -> Void

    private let root: URL
    private let manifest: [KokoroCoreMLManifest.File]
    private let session: Session
    private let compiler: Compiler
    private let sleeper: Sleeper
    private let admission: (@Sendable () async -> Void)?
    /// A file is asked for this many times before the install gives up on it.
    public static let maximumAttempts = 5
    /// The wait before attempt n+1 when the server named none: 2, 4, 8, 16 s.
    static func backoff(afterAttempt attempt: Int) -> TimeInterval { min(60, pow(2, Double(attempt))) }
    /// The longest wait a server is granted. Hugging Face's window is five minutes, and a wait
    /// that long reads as a hang on the veil; a shorter one costs at most one more refused request,
    /// answered with the time still left.
    public static let maximumServerWait: TimeInterval = 120
    /// The wait before attempt `attempt + 1`: what the server asked for, held to
    /// `maximumServerWait`, else the backoff.
    static func wait(afterAttempt attempt: Int, serverAsked: TimeInterval?) -> TimeInterval {
        guard let serverAsked, serverAsked > 0 else { return backoff(afterAttempt: attempt) }
        return min(serverAsked, maximumServerWait)
    }
    private static let log = Logger(subsystem: "com.t2s.reader", category: "kokoro.install")

    /// `root` is the revision directory, e.g. `…/KokoroCoreML/2e878c6a`. `admission` is awaited
    /// before each compile.
    public init(root: URL,
                manifest: [KokoroCoreMLManifest.File] = KokoroCoreMLManifest.files,
                session: Session = .wifi(),
                compiler: @escaping Compiler = { try await MLModel.compileModel(at: $0) },
                sleeper: @escaping Sleeper = { seconds in try? await Task.sleep(for: .seconds(seconds)) },
                admission: (@Sendable () async -> Void)? = nil) {
        self.root = root
        self.manifest = manifest
        self.session = session
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

        // What this install cost, for the timing log (`KokoroInstallTally`): a phone's fresh install
        // is watched from a Mac through that log, since the system log does not reach one.
        let tally = OSAllocatedUnfairLock(initialState: KokoroInstallTally())
        do {
            // The session is closed as soon as the downloads are done, whichever way: the compiles
            // that follow take minutes and have no use for its connections.
            defer { session.close() }
            try await downloadMissingFiles(progress: progress, tally: tally)
        }
        try await compileMissingStages(progress: progress, tally: tally)
        try removeCompiledSources()
        KokoroCoreMLEngine.timing(tally.withLock { $0.summary() })

        switch KokoroCoreMLResources.locate(installedIn: root) {
        case .success(let located): return located
        case .failure(let failure): throw Failure.compile(failure.errorDescription ?? "\(failure)")
        }
    }

    // MARK: Download

    private func downloadMissingFiles(progress: @escaping @Sendable (Progress) -> Void,
                                      tally: OSAllocatedUnfairLock<KokoroInstallTally>) async throws {
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
            let base = done
            // A stage's bucket variants share their weights — the manifest lists 619 MB of which
            // 238 MB is unique — so a file whose bytes are already staged under another path is
            // copied from there, not fetched again.
            if let twin = stagedTwin(of: file) {
                Self.log.notice("copying \(file.path, privacy: .public) from \(twin.lastPathComponent, privacy: .public)")
                KokoroCoreMLEngine.timing("kokoro install copying \(file.path) from \(twin.lastPathComponent)")
                try? FileManager.default.removeItem(at: part)
                try FileManager.default.copyItem(at: twin, to: part)
                tally.withLock { $0.copied(bytes: file.byteCount) }
            } else {
                Self.log.notice("downloading \(file.path, privacy: .public) (\(file.byteCount, privacy: .public) bytes)")
                KokoroCoreMLEngine.timing("kokoro install downloading \(file.path) (\(file.byteCount) bytes)")
                // A refusal the server may lift (429, a 5xx, a dropped connection) is tried again after
                // a wait — the server's own, else doubling from two seconds — up to `maximumAttempts`;
                // anything else (a 404, a checksum) fails the install at once. The `.part` stays
                // between attempts, a 429's too (nothing was wrong with its bytes): the next attempt
                // asks for the rest of it, so a drop three-quarters through the 15 s generator's
                // 67 MB does not cost those bytes again. The SHA-256 below is the safety net.
                var attempt = 0
                while true {
                    attempt += 1
                    do {
                        try await session.download(file.url, part, { bytes in
                            progress(.downloading(bytes: base + min(bytes, file.byteCount), totalBytes: total))
                        }, {
                            progress(.waitingForNetwork(totalBytes: total))
                        })
                        tally.withLock { $0.downloaded(bytes: file.byteCount) }
                        break
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        let refusal = error as? HTTPStatusError
                        let status = refusal?.status
                        Self.log.error("download failed for \(file.path, privacy: .public) (attempt \(attempt, privacy: .public)): \(String(describing: error), privacy: .public)")
                        guard Self.isRetryable(error), attempt < Self.maximumAttempts else {
                            KokoroCoreMLEngine.timing("kokoro install failed: \(file.path) after \(attempt) attempt(s), \(status.map { "HTTP \($0)" } ?? String(describing: error))")
                            throw Failure.download(file.path, status: status)
                        }
                        let delay = Self.wait(afterAttempt: attempt, serverAsked: refusal?.retryAfter)
                        KokoroCoreMLEngine.timing("kokoro install retry \(attempt + 1) for \(file.path) in \(KokoroCoreMLEngine.fixed(delay, 0)) s after \(Self.describe(refusal))")
                        tally.withLock { $0.retried() }
                        progress(.retrying(path: file.path, attempt: attempt + 1, after: delay))
                        await sleeper(delay)
                        try Task.checkCancellation()
                    }
                }
            }
            guard try Self.matches(part, file) else {
                try? FileManager.default.removeItem(at: part)
                Self.log.error("checksum mismatch for \(file.path, privacy: .public)")
                KokoroCoreMLEngine.timing("kokoro install failed: checksum mismatch for \(file.path)")
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

    /// The timing log's account of a refusal: the status, what the server asked to wait, and its
    /// rate-limit headers as sent — enough to tell a spent quota (`r=0`) from a blocklist, the open
    /// question of the 11 Pro's 429s on 2026-09-10.
    static func describe(_ refusal: HTTPStatusError?) -> String {
        guard let refusal else { return "a dropped connection" }
        var text = "HTTP \(refusal.status)"
        if let asked = refusal.retryAfter { text += ", asked \(KokoroCoreMLEngine.fixed(asked, 0)) s" }
        if let headers = refusal.rateLimit { text += " (\(headers))" }
        return text
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

    private func compileMissingStages(progress: @escaping @Sendable (Progress) -> Void,
                                      tally: OSAllocatedUnfairLock<KokoroInstallTally>) async throws {
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
                KokoroCoreMLEngine.timing("kokoro install failed: compile \(stage.name): \(String(describing: error))")
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
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
            Self.log.notice("compiled \(stage.name, privacy: .public) in \(seconds, format: .fixed(precision: 1), privacy: .public) s (\(compiledCount, privacy: .public)/\(all.count, privacy: .public))")
            KokoroCoreMLEngine.timing("kokoro install compiled \(stage.name) in \(KokoroCoreMLEngine.fixed(seconds, 1)) s (\(compiledCount)/\(all.count))")
            tally.withLock { $0.compiled(seconds: seconds) }
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

    /// Per task, so `taskIsWaitingForConnectivity` reaches the file being fetched over the shared session.
    fileprivate final class ConnectivityDelegate: NSObject, URLSessionTaskDelegate {
        private let onWaiting: @Sendable () -> Void
        init(onWaiting: @escaping @Sendable () -> Void) { self.onWaiting = onWaiting }
        func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) { onWaiting() }
    }
}

extension KokoroCoreMLInstall.Session {
    /// One `URLSession` for every file of the install — the session per file of 2026-09-10 was
    /// 72 TLS handshakes and 72 redirect chains through huggingface.co to its CDN per install —
    /// that only downloads over Wi-Fi (no expensive or constrained paths) and waits for one rather
    /// than fail, streaming each file to disk as it arrives. Invalidated by `close`.
    public static func wifi() -> Self {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 6 * 3600
        return Self(urlSession: URLSession(configuration: configuration))
    }

    /// Over `urlSession`: `wifi()`'s, or a test's with a scripted `URLProtocol`.
    init(urlSession: URLSession) {
        self.init(download: { url, destination, onBytes, onWaiting in
            try await Self.fetch(url, into: destination, with: urlSession, onBytes: onBytes, onWaiting: onWaiting)
        }, close: { urlSession.finishTasksAndInvalidate() })
    }

    /// What to do with the answer to a request for the bytes of a file from `offset` on.
    enum Reception: Equatable {
        /// A 206: the body is the rest of the file, and goes after what is there.
        case append
        /// A 200 — the server has no `Range` — or any success to a request from the start: the body
        /// is the whole file.
        case replace
        /// A 416: what is there is no head of the file (longer than it, or the file changed under
        /// it); ask again from the start.
        case restart
    }

    static func reception(of response: HTTPURLResponse, resumingFrom offset: Int) throws -> Reception {
        switch response.statusCode {
        case 206 where offset > 0: return .append
        case 200 ... 299: return .replace
        case 416 where offset > 0: return .restart
        default: throw KokoroCoreMLInstall.HTTPStatusError(response)
        }
    }

    /// The request for `url`: the whole file, or the bytes from `offset` on. Always to the
    /// `huggingface.co` URL: its CDN redirect is a signed URL that expires within the hour, so
    /// `URLSession`'s own resume data, which embeds it, would not do.
    static func request(for url: URL, resumingFrom offset: Int) -> URLRequest {
        var request = URLRequest(url: url)
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        return request
    }

    private static func fetch(_ url: URL, into destination: URL, with session: URLSession,
                              onBytes: @escaping @Sendable (Int) -> Void,
                              onWaiting: @escaping @Sendable () -> Void) async throws {
        let path = destination.path(percentEncoded: false)
        // The head an earlier attempt left, asked to be continued.
        var offset = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int ?? 0
        while true {
            let (bytes, response) = try await session.bytes(for: Self.request(for: url, resumingFrom: offset),
                                                            delegate: KokoroCoreMLInstall.ConnectivityDelegate(onWaiting: onWaiting))
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            switch try Self.reception(of: http, resumingFrom: offset) {
            case .append: break
            case .replace: offset = 0
            case .restart: offset = 0; continue
            }
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(offset))
            var written = offset
            var buffer = Data()
            buffer.reserveCapacity(1 << 20)
            func flush() throws {
                guard !buffer.isEmpty else { return }
                try handle.write(contentsOf: buffer)
                written += buffer.count
                buffer.removeAll(keepingCapacity: true)
                onBytes(written)
            }
            do {
                for try await byte in bytes {
                    buffer.append(byte)
                    if buffer.count >= 1 << 20 { try flush() }
                }
            } catch {
                try? flush()                                          // what arrived is what the next attempt resumes from
                throw error
            }
            try flush()
            return
        }
    }
}
