import CryptoKit
import Foundation
import Testing
@testable import T2SKokoro

/// The installer over a fake network and a fake compiler, in a temporary root: what it downloads,
/// what it skips, what it verifies, and the layout it leaves.
@Suite(.serialized) struct KokoroCoreMLInstallTests {
    /// A tiny manifest: every stage (three files each), one voice, the two runtime files — the shape
    /// of the real one, at a size a test can hash.
    struct Fixture {
        let root: URL
        let bytes: [String: Data]
        let manifest: [KokoroCoreMLManifest.File]

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appending(path: "T2SKokoroInstall-\(UUID().uuidString)", directoryHint: .isDirectory)
            var bytes: [String: Data] = [:]
            var manifest: [KokoroCoreMLManifest.File] = []
            var entries: [(String, String)] = []
            for name in KokoroCoreMLResources.stageNames() {
                entries.append(("coreml/\(name).mlpackage/Data/com.apple.CoreML/model.mlmodel", "model of \(name)"))
                entries.append(("coreml/\(name).mlpackage/Data/com.apple.CoreML/weights/weight.bin", "weights of \(name)"))
                entries.append(("coreml/\(name).mlpackage/Manifest.json", "{}"))
            }
            entries += [
                ("voices/af_heart.bin", "voice"),
                ("runtime/kokoro-vocab.json", "{\"vocab\":{}}"),
                ("runtime/hnsf_weights.json", "{\"linear_weights\":[],\"linear_bias\":0}"),
            ]
            for (path, content) in entries {
                let data = Data(content.utf8)
                bytes[path] = data
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                manifest.append(KokoroCoreMLManifest.File(path, sha256: digest, byteCount: data.count))
            }
            self.bytes = bytes
            self.manifest = manifest
        }

        /// A downloader that serves the fixture's bytes for the manifest's URLs and records what it served.
        func downloader(served: OSAllocatedUnfairLockBox<[String]>, corrupting: Set<String> = []) -> KokoroCoreMLInstall.Downloader {
            let bytes = self.bytes
            return { url, destination, onBytes, _ in
                let path = url.path().components(separatedBy: "/resolve/").last!.split(separator: "/").dropFirst().joined(separator: "/")
                served.value.append(path)
                guard var data = bytes[path] else { throw URLError(.fileDoesNotExist) }
                if corrupting.contains(path) { data.append(0) }
                try data.write(to: destination)
                onBytes(data.count)
            }
        }

        /// The fixture's downloader as the installer's session, with nothing to close.
        func session(served: OSAllocatedUnfairLockBox<[String]>, corrupting: Set<String> = []) -> KokoroCoreMLInstall.Session {
            .init(download: downloader(served: served, corrupting: corrupting))
        }

        /// A compiler that turns a package directory into a directory with a marker file.
        static let compiler: KokoroCoreMLInstall.Compiler = { package in
            let produced = FileManager.default.temporaryDirectory
                .appending(path: "compiled-\(UUID().uuidString).mlmodelc", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: produced, withIntermediateDirectories: true)
            try Data(package.lastPathComponent.utf8).write(to: produced.appending(path: "compiled-from"))
            return produced
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func theManifestIsCompleteAndConsistent() {
        let files = KokoroCoreMLManifest.files
        #expect(files.count == 72)
        #expect(KokoroCoreMLManifest.totalByteCount == 619_234_624)
        let everyHashIsHex = files.allSatisfy { $0.sha256.count == 64 && $0.sha256.allSatisfy(\.isHexDigit) }
        #expect(everyHashIsHex)
        let everySizeIsPositive = files.allSatisfy { $0.byteCount > 0 }
        #expect(everySizeIsPositive)
        #expect(Set(files.map(\.path)).count == 72)
        // Three files per staged stage, all fourteen stages.
        for name in KokoroCoreMLResources.stageNames() {
            let stageFiles = files.filter { $0.path.hasPrefix("coreml/\(name).mlpackage/") }
            #expect(stageFiles.count == 3, "\(name)")
        }
        #expect(files.filter { $0.path.hasPrefix("voices/") }.count == 28)
        #expect(files.map(\.path).contains("runtime/kokoro-vocab.json"))
        #expect(files.map(\.path).contains("runtime/hnsf_weights.json"))
        let heart = files.first { $0.path == "voices/af_heart.bin" }!
        #expect(heart.url.absoluteString
                == "https://huggingface.co/mattmireles/kokoro-coreml/resolve/\(KokoroCoreMLResources.modelRevision)/voices/af_heart.bin")
        let alloy = files.first { $0.path == "voices/af_alloy.bin" }!
        #expect(alloy.repositoryPath == "kokoro.js/voices/af_alloy.bin")
    }

    /// A fresh root: every file downloaded, every stage compiled, the sources removed, the layout locatable.
    @Test func installsEverythingIntoTheCompiledLayout() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let served = OSAllocatedUnfairLockBox<[String]>([])
        let progress = OSAllocatedUnfairLockBox<[KokoroCoreMLInstall.Progress]>([])
        let installer = KokoroCoreMLInstall(root: fixture.root, manifest: fixture.manifest,
                                            session: fixture.session(served: served), compiler: Fixture.compiler)

        _ = try await installer.install { progress.value.append($0) }

        // Every distinct content fetched exactly once (the fixture's Manifest.json files are all "{}",
        // so they are one download and copies), every path present afterwards.
        let hashOf = Dictionary(uniqueKeysWithValues: fixture.manifest.map { ($0.path, $0.sha256) })
        #expect(Set(served.value.map { hashOf[$0]! }) == Set(fixture.manifest.map(\.sha256)))
        #expect(served.value.count == Set(fixture.manifest.map(\.sha256)).count)
        let compiled = fixture.root.appending(path: "compiled/kokoro_duration_t128.mlmodelc/compiled-from")
        #expect(try String(contentsOf: compiled, encoding: .utf8) == "kokoro_duration_t128.mlpackage")
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appending(path: "staging/coreml/kokoro_duration_t128.mlpackage").path()))
        #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: "staging/voices/af_heart.bin").path()))
        // The bar: bytes climb to the total, then the compile counts every stage.
        let total = fixture.manifest.reduce(0) { $0 + $1.byteCount }
        let stageCount = KokoroCoreMLResources.stageNames().count
        #expect(progress.value.contains(.downloading(bytes: total, totalBytes: total)))
        #expect(progress.value.last == .compiling(stage: stageCount, totalStages: stageCount))
    }

    /// A downloader that fails a given path with an HTTP status a set number of times, then serves it.
    func flakyDownloader(_ fixture: Fixture, failing path: String, status: Int, times: Int, retryAfter: TimeInterval? = nil,
                         served: OSAllocatedUnfairLockBox<[String]>) -> KokoroCoreMLInstall.Downloader {
        let inner = fixture.downloader(served: served)
        let failures = OSAllocatedUnfairLockBox(times)
        return { url, destination, onBytes, onWaiting in
            let requested = url.path().components(separatedBy: "/resolve/").last!.split(separator: "/").dropFirst().joined(separator: "/")
            if requested == path, failures.value > 0 {
                failures.value -= 1
                served.value.append(requested)
                throw KokoroCoreMLInstall.HTTPStatusError(status: status, retryAfter: retryAfter)
            }
            try await inner(url, destination, onBytes, onWaiting)
        }
    }

    /// A 429 on one file is retried after the server's `Retry-After`, and the install completes.
    @Test func retriesAThrottledFileAndCompletes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let served = OSAllocatedUnfairLockBox<[String]>([])
        let sleeps = OSAllocatedUnfairLockBox<[TimeInterval]>([])
        let progress = OSAllocatedUnfairLockBox<[KokoroCoreMLInstall.Progress]>([])
        let installer = KokoroCoreMLInstall(
            root: fixture.root, manifest: fixture.manifest,
            session: .init(download: flakyDownloader(fixture, failing: "voices/af_heart.bin", status: 429, times: 1, retryAfter: 7, served: served)),
            compiler: Fixture.compiler, sleeper: { seconds in sleeps.value.append(seconds) })

        _ = try await installer.install { progress.value.append($0) }

        #expect(served.value.filter { $0 == "voices/af_heart.bin" }.count == 2)   // once refused, once served
        #expect(sleeps.value == [7])                                               // the server's own delay
        #expect(progress.value.contains(.retrying(path: "voices/af_heart.bin", attempt: 2, after: 7)))
        #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: "staging/voices/af_heart.bin").path()))
    }

    /// Without a `Retry-After`, the waits double from two seconds; a file that keeps failing is
    /// given up after five attempts, and the failure names the status.
    @Test func backsOffAndGivesUpAfterFiveAttempts() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let served = OSAllocatedUnfairLockBox<[String]>([])
        let sleeps = OSAllocatedUnfairLockBox<[TimeInterval]>([])
        let installer = KokoroCoreMLInstall(
            root: fixture.root, manifest: fixture.manifest,
            session: .init(download: flakyDownloader(fixture, failing: "runtime/kokoro-vocab.json", status: 503, times: 99, served: served)),
            compiler: Fixture.compiler, sleeper: { seconds in sleeps.value.append(seconds) })

        await #expect(throws: KokoroCoreMLInstall.Failure.download("runtime/kokoro-vocab.json", status: 503)) {
            _ = try await installer.install { _ in }
        }
        #expect(served.value.filter { $0 == "runtime/kokoro-vocab.json" }.count == 5)
        #expect(sleeps.value == [2, 4, 8, 16])
    }

    /// A 404 is not a passing condition: no retry, no sleep, the failure names it.
    @Test func doesNotRetryAMissingFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let served = OSAllocatedUnfairLockBox<[String]>([])
        let sleeps = OSAllocatedUnfairLockBox<[TimeInterval]>([])
        let installer = KokoroCoreMLInstall(
            root: fixture.root, manifest: fixture.manifest,
            session: .init(download: flakyDownloader(fixture, failing: "voices/af_heart.bin", status: 404, times: 99, served: served)),
            compiler: Fixture.compiler, sleeper: { seconds in sleeps.value.append(seconds) })

        await #expect(throws: KokoroCoreMLInstall.Failure.download("voices/af_heart.bin", status: 404)) {
            _ = try await installer.install { _ in }
        }
        #expect(served.value.filter { $0 == "voices/af_heart.bin" }.count == 1)
        #expect(sleeps.value.isEmpty)
    }

    /// A downloader that, for `path`, drops the connection after `keeping` bytes on the first
    /// request (never, when nil), answers the requests after that with `statuses` in turn, and then
    /// serves the rest of the file from wherever the `.part` stopped — as the live session does with
    /// a `Range` — recording the size of the part it found on each request.
    func resumingDownloader(_ fixture: Fixture, for path: String, droppingAfter keeping: Int?, then statuses: [Int] = [],
                            retryAfter: TimeInterval? = nil,
                            served: OSAllocatedUnfairLockBox<[String]>, partSizes: OSAllocatedUnfairLockBox<[Int]>) -> KokoroCoreMLInstall.Downloader {
        let inner = fixture.downloader(served: served)
        let bytes = fixture.bytes
        let refusals = OSAllocatedUnfairLockBox(statuses)
        let dropped = OSAllocatedUnfairLockBox(keeping == nil)
        return { url, destination, onBytes, onWaiting in
            let requested = url.path().components(separatedBy: "/resolve/").last!.split(separator: "/").dropFirst().joined(separator: "/")
            guard requested == path else { return try await inner(url, destination, onBytes, onWaiting) }
            let have = (try? Data(contentsOf: destination))?.count ?? 0
            partSizes.value.append(have)
            served.value.append(requested)
            let data = bytes[path]!
            if !dropped.value, let keeping {
                dropped.value = true
                try data.prefix(keeping).write(to: destination)
                throw URLError(.networkConnectionLost)
            }
            if !refusals.value.isEmpty {
                throw KokoroCoreMLInstall.HTTPStatusError(status: refusals.value.removeFirst(), retryAfter: retryAfter)
            }
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data.dropFirst(have))
            onBytes(data.count)
        }
    }

    /// A connection dropped mid-file leaves the `.part`; a 429 in between keeps it too; the attempt
    /// after that is asked for the rest and appends it.
    @Test func resumesAFileFromWhereTheConnectionDropped() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let served = OSAllocatedUnfairLockBox<[String]>([])
        let partSizes = OSAllocatedUnfairLockBox<[Int]>([])
        let sleeps = OSAllocatedUnfairLockBox<[TimeInterval]>([])
        let progress = OSAllocatedUnfairLockBox<[KokoroCoreMLInstall.Progress]>([])
        let installer = KokoroCoreMLInstall(
            root: fixture.root, manifest: fixture.manifest,
            session: .init(download: resumingDownloader(fixture, for: "voices/af_heart.bin", droppingAfter: 2, then: [429], retryAfter: 3,
                                                        served: served, partSizes: partSizes)),
            compiler: Fixture.compiler, sleeper: { seconds in sleeps.value.append(seconds) })

        _ = try await installer.install { progress.value.append($0) }

        // Dropped with two bytes down, refused with the two still there, then continued from them.
        #expect(partSizes.value == [0, 2, 2])
        #expect(sleeps.value == [2, 3])
        #expect(progress.value.contains(.retrying(path: "voices/af_heart.bin", attempt: 2, after: 2)))
        #expect(progress.value.contains(.retrying(path: "voices/af_heart.bin", attempt: 3, after: 3)))
        let voice = fixture.root.appending(path: "staging/voices/af_heart.bin")
        #expect(try Data(contentsOf: voice) == fixture.bytes["voices/af_heart.bin"])
        #expect(!FileManager.default.fileExists(atPath: voice.appendingPathExtension("part").path()))
    }

    /// A `.part` an earlier launch left is continued, not fetched from the start.
    @Test func continuesAPartLeftByAnEarlierLaunch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let voices = fixture.root.appending(path: "staging/voices", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: voices, withIntermediateDirectories: true)
        try fixture.bytes["voices/af_heart.bin"]!.prefix(3).write(to: voices.appending(path: "af_heart.bin.part"))
        let served = OSAllocatedUnfairLockBox<[String]>([])
        let partSizes = OSAllocatedUnfairLockBox<[Int]>([])
        let installer = KokoroCoreMLInstall(
            root: fixture.root, manifest: fixture.manifest,
            session: .init(download: resumingDownloader(fixture, for: "voices/af_heart.bin", droppingAfter: nil, served: served, partSizes: partSizes)),
            compiler: Fixture.compiler)

        _ = try await installer.install { _ in }

        #expect(partSizes.value == [3])
        #expect(try Data(contentsOf: voices.appending(path: "af_heart.bin")) == fixture.bytes["voices/af_heart.bin"])
    }

    /// A server's wait is honoured up to two minutes: Hugging Face's window is five, and a wait
    /// that long reads as a hang on the veil; a shorter one costs one more refused request at most.
    @Test func aServersWaitIsHeldToTwoMinutes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let served = OSAllocatedUnfairLockBox<[String]>([])
        let sleeps = OSAllocatedUnfairLockBox<[TimeInterval]>([])
        let progress = OSAllocatedUnfairLockBox<[KokoroCoreMLInstall.Progress]>([])
        let installer = KokoroCoreMLInstall(
            root: fixture.root, manifest: fixture.manifest,
            session: .init(download: flakyDownloader(fixture, failing: "voices/af_heart.bin", status: 429, times: 1, retryAfter: 217, served: served)),
            compiler: Fixture.compiler, sleeper: { seconds in sleeps.value.append(seconds) })

        _ = try await installer.install { progress.value.append($0) }

        #expect(sleeps.value == [KokoroCoreMLInstall.maximumServerWait])
        #expect(progress.value.contains(.retrying(path: "voices/af_heart.bin", attempt: 2, after: 120)))
    }

    /// The wait a 429 names: `Retry-After` in seconds or as a date, the reset headers as seconds or
    /// an epoch, Hugging Face's `RateLimit` `t=` — the most specific first, a date already passed
    /// ignored — and the headers themselves kept for the timing line.
    @Test func theWaitComesFromTheMostSpecificRateLimitHeader() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)                  // Fri, 15 Jan 2027 08:00:00 GMT
        let url = URL(string: "https://huggingface.co/mattmireles/kokoro-coreml/resolve/x/voices/af_heart.bin")!
        func refused(_ headers: [String: String]) -> KokoroCoreMLInstall.HTTPStatusError {
            .init(HTTPURLResponse(url: url, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: headers)!, now: now)
        }
        #expect(refused(["Retry-After": "30"]).retryAfter == 30)
        #expect(refused(["Retry-After": "Fri, 15 Jan 2027 08:00:45 GMT"]).retryAfter == 45)
        #expect(refused(["RateLimit-Reset": "50"]).retryAfter == 50)
        #expect(refused(["X-RateLimit-Reset": "1800000217"]).retryAfter == 217)      // an epoch
        #expect(refused(["RateLimit": "\"resolvers\";r=0;t=217"]).retryAfter == 217)  // Hugging Face's
        #expect(refused(["Retry-After": "30", "RateLimit": "\"resolvers\";r=0;t=217"]).retryAfter == 30)
        #expect(refused(["Retry-After": "Fri, 15 Jan 2027 07:59:00 GMT", "RateLimit": "\"resolvers\";r=0;t=217"]).retryAfter == 217)
        #expect(refused(["Retry-After": "soon"]).retryAfter == nil)
        #expect(refused([:]).retryAfter == nil)
        #expect(refused([:]).rateLimit == nil)

        let huggingFace = refused(["RateLimit": "\"resolvers\";r=0;t=217", "RateLimit-Policy": "\"resolvers\";q=3000;w=300"])
        #expect(huggingFace.status == 429)
        #expect(huggingFace.rateLimit == "ratelimit: \"resolvers\";r=0;t=217, ratelimit-policy: \"resolvers\";q=3000;w=300")
        #expect(KokoroCoreMLInstall.describe(huggingFace)
                == "HTTP 429, asked 217 s (ratelimit: \"resolvers\";r=0;t=217, ratelimit-policy: \"resolvers\";q=3000;w=300)")
        #expect(KokoroCoreMLInstall.describe(nil) == "a dropped connection")
        #expect(KokoroCoreMLInstall.wait(afterAttempt: 1, serverAsked: 217) == 120)
        #expect(KokoroCoreMLInstall.wait(afterAttempt: 1, serverAsked: 7) == 7)
        #expect(KokoroCoreMLInstall.wait(afterAttempt: 3, serverAsked: nil) == 8)
    }

    /// A resumed request asks for the rest of the file, and the server's answer decides what
    /// happens to the part: a 206 is appended, a 200 replaces it, a 416 asks again from the start,
    /// anything else is the status.
    @Test func aResumedRequestAsksForTheRestAndTakesWhatTheServerAnswers() throws {
        typealias Session = KokoroCoreMLInstall.Session
        let url = URL(string: "https://huggingface.co/mattmireles/kokoro-coreml/resolve/x/voices/af_heart.bin")!
        #expect(Session.request(for: url, resumingFrom: 0).value(forHTTPHeaderField: "Range") == nil)
        #expect(Session.request(for: url, resumingFrom: 1234).value(forHTTPHeaderField: "Range") == "bytes=1234-")
        func answer(_ status: Int, from offset: Int) throws -> Session.Reception {
            try Session.reception(of: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!,
                                  resumingFrom: offset)
        }
        #expect(try answer(206, from: 1234) == .append)
        #expect(try answer(200, from: 1234) == .replace)
        #expect(try answer(416, from: 1234) == .restart)
        #expect(try answer(200, from: 0) == .replace)
        #expect(throws: KokoroCoreMLInstall.HTTPStatusError(status: 416)) { try answer(416, from: 0) }
        #expect(throws: KokoroCoreMLInstall.HTTPStatusError(status: 503)) { try answer(503, from: 1234) }
    }

    /// The live session against a scripted server, every request through the one `URLSession`: a
    /// part left by a drop is asked to be continued, a 206 is appended, a 200 replaces, a 416 is
    /// asked again from the start, and a 429 comes back as its status and wait with the part
    /// untouched. The drop itself is not scripted: a `URLProtocol` that fails after delivering a
    /// response makes `URLSession.bytes(for:)` throw as a whole (probed 2026-09-11), so the bytes
    /// that a real drop leaves — headers in, body cut — can only be left here by hand.
    @Test func theLiveSessionResumesWithARangeOverOneURLSession() async throws {
        let part = FileManager.default.temporaryDirectory.appending(path: "T2SKokoroResume-\(UUID().uuidString).part")
        defer { try? FileManager.default.removeItem(at: part) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedServer.self]
        let session = KokoroCoreMLInstall.Session(urlSession: URLSession(configuration: configuration))
        defer { session.close() }
        let url = URL(string: "https://huggingface.co/mattmireles/kokoro-coreml/resolve/x/voices/af_heart.bin")!
        let body = Data("0123456789".utf8)
        let reported = OSAllocatedUnfairLockBox<[Int]>([])
        let onBytes: @Sendable (Int) -> Void = { reported.value.append($0) }
        func rangeAsked() -> String? { ScriptedServer.requests.value.last?.value(forHTTPHeaderField: "Range") }
        ScriptedServer.requests.value = []

        // The four bytes a drop left in the part: the next request asks for the rest; a 206 is appended.
        try body.prefix(4).write(to: part)
        ScriptedServer.answers.value = [.init(status: 206, headers: ["Content-Range": "bytes 4-9/10"], body: body.dropFirst(4))]
        try await session.download(url, part, onBytes, {})
        #expect(rangeAsked() == "bytes=4-")
        #expect(try Data(contentsOf: part) == body)
        #expect(reported.value.last == 10)

        // A server without `Range` answers the whole file with a 200: the part is replaced, not extended.
        ScriptedServer.answers.value = [.init(status: 200, body: body)]
        try await session.download(url, part, onBytes, {})
        #expect(rangeAsked() == "bytes=10-")
        #expect(try Data(contentsOf: part) == body)

        // A 416 — the part is no head of the file — is asked again from the start, and that answer kept.
        ScriptedServer.answers.value = [.init(status: 416), .init(status: 200, body: body.prefix(7))]
        try await session.download(url, part, onBytes, {})
        #expect(ScriptedServer.requests.value.suffix(2).map { $0.value(forHTTPHeaderField: "Range") } == ["bytes=10-", nil])
        #expect(try Data(contentsOf: part) == body.prefix(7))

        // A 429 is its status and the wait its headers name; the part is untouched.
        ScriptedServer.answers.value = [.init(status: 429, headers: ["RateLimit": "\"resolvers\";r=0;t=217"])]
        await #expect(throws: KokoroCoreMLInstall.HTTPStatusError(status: 429, retryAfter: 217, rateLimit: "ratelimit: \"resolvers\";r=0;t=217")) {
            try await session.download(url, part, onBytes, {})
        }
        #expect(try Data(contentsOf: part) == body.prefix(7))
        #expect(ScriptedServer.requests.value.count == 5)
    }

    /// Two manifest files with the same content are one download: the second is copied from the
    /// first. (The real manifest's bucket variants share their weights — 619 MB listed, 238 MB unique.)
    @Test func aFileWithTheSameContentIsCopiedNotDownloaded() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let heart = fixture.manifest.first { $0.path == "voices/af_heart.bin" }!
        let twin = KokoroCoreMLManifest.File("voices/af_twin.bin", sha256: heart.sha256, byteCount: heart.byteCount)
        let served = OSAllocatedUnfairLockBox<[String]>([])
        // The fixture's downloader has no bytes for the twin: asking for it over the network fails.
        let installer = KokoroCoreMLInstall(root: fixture.root, manifest: fixture.manifest + [twin],
                                            session: fixture.session(served: served), compiler: Fixture.compiler)

        _ = try await installer.install { _ in }

        #expect(!served.value.contains("voices/af_twin.bin"))
        #expect(served.value.contains("voices/af_heart.bin"))
        let staged = fixture.root.appending(path: "staging/voices/af_twin.bin")
        #expect(try Data(contentsOf: staged) == fixture.bytes["voices/af_heart.bin"])
    }

    /// A second run over an installed root downloads nothing and compiles nothing.
    @Test func aSecondInstallIsFree() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = OSAllocatedUnfairLockBox<[String]>([])
        _ = try await KokoroCoreMLInstall(root: fixture.root, manifest: fixture.manifest,
                                          session: fixture.session(served: first), compiler: Fixture.compiler).install { _ in }
        let second = OSAllocatedUnfairLockBox<[String]>([])
        let compiles = OSAllocatedUnfairLockBox(0)
        let compiler: KokoroCoreMLInstall.Compiler = { package in compiles.value += 1; return try await Fixture.compiler(package) }
        _ = try await KokoroCoreMLInstall(root: fixture.root, manifest: fixture.manifest,
                                          session: fixture.session(served: second), compiler: compiler).install { _ in }
        #expect(second.value.isEmpty)
        #expect(compiles.value == 0)
    }

    /// A file already present at its hash is skipped; one present at the wrong bytes is fetched again.
    @Test func resumesAroundFilesAlreadyThere() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let staging = fixture.root.appending(path: "staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging.appending(path: "voices"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging.appending(path: "runtime"), withIntermediateDirectories: true)
        try fixture.bytes["voices/af_heart.bin"]!.write(to: staging.appending(path: "voices/af_heart.bin"))
        try Data("stale".utf8).write(to: staging.appending(path: "runtime/kokoro-vocab.json"))
        let served = OSAllocatedUnfairLockBox<[String]>([])
        _ = try await KokoroCoreMLInstall(root: fixture.root, manifest: fixture.manifest,
                                          session: fixture.session(served: served), compiler: Fixture.compiler).install { _ in }
        #expect(!served.value.contains("voices/af_heart.bin"))
        #expect(served.value.contains("runtime/kokoro-vocab.json"))
        #expect(try String(contentsOf: staging.appending(path: "runtime/kokoro-vocab.json"), encoding: .utf8) == "{\"vocab\":{}}")
    }

    /// A download whose bytes do not hash as the manifest says is refused and removed, never kept.
    @Test func aCorruptDownloadIsRefused() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let served = OSAllocatedUnfairLockBox<[String]>([])
        let installer = KokoroCoreMLInstall(root: fixture.root, manifest: fixture.manifest,
                                            session: fixture.session(served: served, corrupting: ["voices/af_heart.bin"]),
                                            compiler: Fixture.compiler)
        await #expect(throws: KokoroCoreMLInstall.Failure.checksumMismatch("voices/af_heart.bin")) {
            _ = try await installer.install { _ in }
        }
        let voice = fixture.root.appending(path: "staging/voices/af_heart.bin")
        #expect(!FileManager.default.fileExists(atPath: voice.path()))
        #expect(!FileManager.default.fileExists(atPath: voice.appendingPathExtension("part").path()))
    }

    /// Every compile waits on the admission gate the app hands in.
    @Test func compilesAreAdmittedThroughTheGate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let admissions = OSAllocatedUnfairLockBox(0)
        let installer = KokoroCoreMLInstall(root: fixture.root, manifest: fixture.manifest,
                                            session: fixture.session(served: OSAllocatedUnfairLockBox([])),
                                            compiler: Fixture.compiler, admission: { admissions.value += 1 })
        _ = try await installer.install { _ in }
        #expect(admissions.value == KokoroCoreMLResources.stageNames().count)
    }

    @Test func theInstalledLayoutIsWhatTheAvailabilityCheckAcceptsAfterAnInstall() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(KokoroCoreMLResources.locate(installedIn: fixture.root) == .failure(.missing("kokoro_duration_t128")))
        let verdict = KokoroCoreMLAvailability.check(bundle: Bundle(for: Marker.self), installRoot: fixture.root)
        #expect(verdict == .unavailable(.notInstalled(.missing("kokoro_duration_t128"))))
    }

    private final class Marker {}
}

/// A server the live session talks to: each request is answered from a script — a status, its
/// headers, a body, or a connection that drops after so many bytes of it — and recorded. The
/// suite is serialized, so the script is one at a time.
private final class ScriptedServer: URLProtocol {
    struct Answer: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
    }
    static let answers = OSAllocatedUnfairLockBox<[Answer]>([])
    static let requests = OSAllocatedUnfairLockBox<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append(request)
        var answers = Self.answers.value
        let answer = answers.isEmpty ? Answer(status: 500) : answers.removeFirst()
        Self.answers.value = answers
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // The body after the response has been handed over, as a server's would arrive.
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) { [self] in
            client?.urlProtocol(self, didLoad: answer.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
