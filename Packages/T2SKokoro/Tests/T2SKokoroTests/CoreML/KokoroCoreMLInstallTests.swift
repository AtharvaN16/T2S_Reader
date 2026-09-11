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
                                            downloader: fixture.downloader(served: served), compiler: Fixture.compiler)

        _ = try await installer.install { progress.value.append($0) }

        #expect(Set(served.value) == Set(fixture.manifest.map(\.path)))
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
            downloader: flakyDownloader(fixture, failing: "voices/af_heart.bin", status: 429, times: 1, retryAfter: 7, served: served),
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
            downloader: flakyDownloader(fixture, failing: "runtime/kokoro-vocab.json", status: 503, times: 99, served: served),
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
            downloader: flakyDownloader(fixture, failing: "voices/af_heart.bin", status: 404, times: 99, served: served),
            compiler: Fixture.compiler, sleeper: { seconds in sleeps.value.append(seconds) })

        await #expect(throws: KokoroCoreMLInstall.Failure.download("voices/af_heart.bin", status: 404)) {
            _ = try await installer.install { _ in }
        }
        #expect(served.value.filter { $0 == "voices/af_heart.bin" }.count == 1)
        #expect(sleeps.value.isEmpty)
    }

    /// A second run over an installed root downloads nothing and compiles nothing.
    @Test func aSecondInstallIsFree() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = OSAllocatedUnfairLockBox<[String]>([])
        _ = try await KokoroCoreMLInstall(root: fixture.root, manifest: fixture.manifest,
                                          downloader: fixture.downloader(served: first), compiler: Fixture.compiler).install { _ in }
        let second = OSAllocatedUnfairLockBox<[String]>([])
        let compiles = OSAllocatedUnfairLockBox(0)
        let compiler: KokoroCoreMLInstall.Compiler = { package in compiles.value += 1; return try await Fixture.compiler(package) }
        _ = try await KokoroCoreMLInstall(root: fixture.root, manifest: fixture.manifest,
                                          downloader: fixture.downloader(served: second), compiler: compiler).install { _ in }
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
                                          downloader: fixture.downloader(served: served), compiler: Fixture.compiler).install { _ in }
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
                                            downloader: fixture.downloader(served: served, corrupting: ["voices/af_heart.bin"]),
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
                                            downloader: fixture.downloader(served: OSAllocatedUnfairLockBox([])),
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
