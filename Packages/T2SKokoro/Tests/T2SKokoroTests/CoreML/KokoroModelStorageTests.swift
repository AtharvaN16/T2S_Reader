import Foundation
import Testing
@testable import T2SKokoro

/// What Settings → Storage measures and reclaims: every downloaded revision, not this launch's.
@Suite struct KokoroModelStorageTests {
    /// An Application Support directory holding two revisions of the model, as a phone that has
    /// been through a revision bump holds them — nothing prunes the install before.
    private func applicationSupport(revisions: [String: Int]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "kokoro-models-\(UUID().uuidString)")
        for (revision, bytes) in revisions {
            let compiled = KokoroCoreMLInstall.modelsDirectory(applicationSupport: root)
                .appending(path: revision)
                .appending(path: "compiled/kokoro_duration_t128.mlmodelc")
            try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
            try Data(repeating: 0, count: bytes).write(to: compiled.appending(path: "weights.bin"))
        }
        // Something of another feature's, beside the models: a delete must not reach it.
        let other = root.appending(path: "Library")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: other.appending(path: "library.sqlite"))
        return root
    }

    @Test func theRevisionRootSitsUnderTheDirectoryADeleteReaches() {
        let support = URL(filePath: "/tmp/support")
        let models = KokoroCoreMLInstall.modelsDirectory(applicationSupport: support)
        #expect(models.lastPathComponent == "KokoroCoreML")
        #expect(KokoroCoreMLInstall.defaultRoot(applicationSupport: support)
            .path(percentEncoded: false).hasPrefix(models.path(percentEncoded: false)))
    }

    @Test func theSizeCountsEveryRevisionOnDisk() throws {
        let support = try applicationSupport(revisions: ["3ffe1347": 2048, "2e878c6a": 1024])
        #expect(KokoroCoreMLInstall.installedBytes(applicationSupport: support) == 3072)
    }

    @Test func theDeleteRemovesEveryRevisionReportsTheBytesAndLeavesTheRestAlone() throws {
        let support = try applicationSupport(revisions: ["3ffe1347": 2048, "2e878c6a": 1024])
        #expect(KokoroCoreMLInstall.removeAll(applicationSupport: support) == 3072)
        #expect(KokoroCoreMLInstall.installedBytes(applicationSupport: support) == 0)
        #expect(!FileManager.default.fileExists(
            atPath: KokoroCoreMLInstall.modelsDirectory(applicationSupport: support).path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(
            atPath: support.appending(path: "Library/library.sqlite").path(percentEncoded: false)))
    }

    /// Nothing to delete is not a failure: the reader may have deleted it on a previous launch, or
    /// never had it at all.
    @Test func aSecondDeleteFreesNothingAndDoesNotThrow() throws {
        let support = try applicationSupport(revisions: ["3ffe1347": 2048])
        #expect(KokoroCoreMLInstall.removeAll(applicationSupport: support) == 2048)
        #expect(KokoroCoreMLInstall.removeAll(applicationSupport: support) == 0)
    }

    /// The verdict is otherwise decided in `init` and only moves forward; a delete is the one thing
    /// that takes the files away mid-session, and the route has to see it.
    @Test @MainActor func theAvailabilityModelSeesADeleteWhenItIsAskedAgain() throws {
        let support = try applicationSupport(revisions: [:])
        let installRoot = KokoroCoreMLInstall.defaultRoot(applicationSupport: support)
        let model = KokoroCoreMLAvailabilityModel(bundle: .main, installRoot: installRoot)
        #expect(model.needsInstall)                                  // nothing installed in this root
        model.installed(KokoroCoreMLResources.Located(stages: [:], voices: [:],
                                                      vocab: installRoot.appending(path: "vocab.json"),
                                                      hnsfWeights: installRoot.appending(path: "hnsf.json"),
                                                      isPrecompiled: true))
        #expect(!model.needsInstall)
        model.recheck()
        #expect(model.needsInstall)
    }
}
