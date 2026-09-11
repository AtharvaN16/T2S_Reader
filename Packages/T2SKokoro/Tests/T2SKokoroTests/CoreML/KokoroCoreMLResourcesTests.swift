import Foundation
import Testing
@testable import T2SKokoro

@Suite struct KokoroCoreMLResourcesTests {
    @Test func stageNamesCoverEveryBucketAndBothDurationModels() {
        #expect(KokoroCoreMLResources.buckets == [3, 7, 10, 15])
        #expect(Set(KokoroCoreMLResources.stageNames()) == [
            "kokoro_duration_t128", "kokoro_duration_t256",
            "kokoro_f0ntrain_t120", "kokoro_f0ntrain_t280", "kokoro_f0ntrain_t400", "kokoro_f0ntrain_t600",
            "kokoro_decoder_pre_3s", "kokoro_decoder_pre_7s", "kokoro_decoder_pre_10s", "kokoro_decoder_pre_15s",
            "kokoro_decoder_har_post_3s", "kokoro_decoder_har_post_7s", "kokoro_decoder_har_post_10s", "kokoro_decoder_har_post_15s",
        ])
    }

    /// Readiness waits for seven plans, not eight: t256 — the plan that is a first launch on the A13
    /// — comes after the 7 s and 10 s buckets, and the three sets together are the fourteen.
    @Test func theReadySetLeavesT256ForAfterReadiness() {
        let ready = KokoroCoreMLResources.stageNames(buckets: KokoroCoreMLResources.readyBuckets,
                                                     durationTokenLengths: KokoroCoreMLResources.readyDurationTokenLengths)
        #expect(Set(ready) == [
            "kokoro_duration_t128", "kokoro_f0ntrain_t120", "kokoro_f0ntrain_t600",
            "kokoro_decoder_pre_3s", "kokoro_decoder_pre_15s", "kokoro_decoder_har_post_3s", "kokoro_decoder_har_post_15s",
        ])
        #expect(KokoroCoreMLResources.laterDurationTokenLengths == [256])
        let later = KokoroCoreMLResources.laterBuckets.flatMap {
            KokoroCoreMLResources.stageNames(buckets: [$0], durationTokenLengths: [])
        } + KokoroCoreMLResources.laterDurationTokenLengths.flatMap {
            KokoroCoreMLResources.stageNames(buckets: [], durationTokenLengths: [$0])
        }
        #expect(Set(ready + later) == Set(KokoroCoreMLResources.stageNames()))
        #expect(ready.count + later.count == 14)
    }

    @Test func anEmptyDirectoryIsMissingItsFirstStage() throws {
        try withTemporaryDirectory { directory in
            #expect(KokoroCoreMLResources.locate(inDirectory: directory) == .failure(.missing("kokoro_duration_t128")))
        }
    }

    /// Exercises the `locate(in:)` bundle path at all: the `.xctest` bundle this suite runs from has
    /// none of the staged `.mlmodelc` bundles, so it fails the same way an empty directory does.
    @Test func aBundleWithNoStagesIsMissingItsFirstStage() {
        #expect(KokoroCoreMLResources.locate(in: Bundle(for: TestBundleMarker.self)) == .failure(.missing("kokoro_duration_t128")))
    }

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func theDevelopmentDirectoryLocates28Voices() throws {
        let located = try KokoroCoreMLResources.locate(inDirectory: KokoroCoreMLResources.developmentDirectory).get()
        #expect(located.voices.count == 28 && located.isPrecompiled == false)
    }

    /// Only ever passed to `Bundle(for:)`, to find the `.xctest` bundle this code was loaded from.
    private final class TestBundleMarker {}

    /// Runs `body` against a fresh directory under the system temporary directory and removes it after.
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "T2SKokoroTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
