import Foundation
import Testing
@testable import T2SKokoro

@Suite struct KokoroCoreMLResourcesTests {
    @Test func stageNamesCoverBothBucketsAndBothDurationModels() {
        #expect(Set(KokoroCoreMLResources.stageNames()) == [
            "kokoro_duration_t128", "kokoro_duration_t256",
            "kokoro_f0ntrain_t280", "kokoro_f0ntrain_t600",
            "kokoro_decoder_pre_7s", "kokoro_decoder_pre_15s",
            "kokoro_decoder_har_post_7s", "kokoro_decoder_har_post_15s",
        ])
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
