import Foundation
import Testing
@testable import T2SKokoro

@Suite struct KokoroResourcesTests {
    @Test func locateReportsTheModelMissingFromAnEmptyDirectory() throws {
        try withTemporaryDirectory { directory in
            #expect(KokoroResources.locate(in: directory) == .failure(.missing("kokoro-v1_0.safetensors")))
        }
    }

    @Test func locateReportsASizeMismatchForATruncatedModel() throws {
        try withTemporaryDirectory { directory in
            try Data(repeating: 0, count: 10).write(to: directory.appending(path: "kokoro-v1_0.safetensors"))
            #expect(KokoroResources.locate(in: directory) == .failure(.sizeMismatch("kokoro-v1_0.safetensors")))
        }
    }

    @Test func sha256HexHashesAFileInStreamedChunks() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appending(path: "abc.txt")
            try Data("abc".utf8).write(to: file)
            let digest = try KokoroResources.sha256Hex(of: file)
            #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        }
    }

    @Test func verifyRejectsFilesThatAreNotTheModel() throws {
        try withTemporaryDirectory { directory in
            let model = directory.appending(path: "kokoro-v1_0.safetensors")
            let voices = directory.appending(path: "voices.npz")
            try Data("not the model".utf8).write(to: model)
            try Data("not the voices".utf8).write(to: voices)
            #expect(throws: KokoroResources.Failure.checksumMismatch("kokoro-v1_0.safetensors")) {
                try KokoroResources.verify(KokoroResources.Located(model: model, voices: voices))
            }
        }
    }

    @Test(.enabled(if: KokoroTestSupport.haveRealFiles))
    func verifyAcceptsTheInstalledModelAndVoices() throws {
        let located = try KokoroResources.locate(in: KokoroResources.developmentDirectory).get()
        try KokoroResources.verify(located)
    }

    @Test func theRuntimeSampleRateIs24kHz() {
        #expect(KokoroRuntime.sampleRate == 24_000)
    }

    /// Runs `body` against a fresh directory under the system temporary directory and removes it after.
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appending(path: "T2SKokoroTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
