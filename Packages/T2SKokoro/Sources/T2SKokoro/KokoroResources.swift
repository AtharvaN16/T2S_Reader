import CryptoKit
import Foundation

/// The two files the Kokoro engine loads, and the checks that prove a copy is the one we measured.
///
/// Deliberately MLX-free: availability probes, preferences and the app's launch path ask these
/// questions long before anything decides to load a model, and must not pay to link MLX to do it.
public enum KokoroResources: Sendable {
    // The weights and the voice styles, as published by KokoroTestApp and installed by
    // `scripts/fetch-kokoro-model.sh`. Sizes and digests are pinned so a truncated download, a
    // half-finished copy or a swapped model is caught before MLX ever sees it.

    public static let modelFileName = "kokoro-v1_0.safetensors"
    public static let modelByteCount = 327_115_152
    public static let modelSHA256 = "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8"

    public static let voicesFileName = "voices.npz"
    public static let voicesByteCount = 14_629_684
    public static let voicesSHA256 = "56dbfa2f2970af2e395397020393d368c5f441d09b3de4e9b77f6222e790f10f"

    /// The first eight characters of ``modelSHA256``. The engine ID carries it, so audio rendered
    /// by a different set of weights lands under a different cache key.
    public static let modelChecksumPrefix = String(modelSHA256.prefix(8))

    /// A directory that holds both files, with existence and sizes already checked.
    public struct Located: Hashable, Sendable {
        public let model: URL
        public let voices: URL

        public init(model: URL, voices: URL) {
            self.model = model
            self.voices = voices
        }
    }

    /// Why a directory cannot serve as the Kokoro resource directory. The payload is the file name.
    public enum Failure: Error, Equatable, Sendable, LocalizedError {
        case missing(String)
        case sizeMismatch(String)
        case checksumMismatch(String)

        public var errorDescription: String? {
            switch self {
            case .missing(let file):
                "The Kokoro voice data is not installed (\(file) is missing). "
                    + "Run scripts/fetch-kokoro-model.sh to install it."
            case .sizeMismatch(let file):
                "The Kokoro voice data is incomplete (\(file) is the wrong size). "
                    + "Run scripts/fetch-kokoro-model.sh to reinstall it."
            case .checksumMismatch(let file):
                "The Kokoro voice data is damaged (\(file) does not match its checksum). "
                    + "Run scripts/fetch-kokoro-model.sh to reinstall it."
            }
        }
    }

    /// Checks that `directory` holds both files at their recorded sizes. Cheap on purpose — no
    /// hashing — so an availability probe can call it on every launch; ``verify(_:)`` does the rest.
    public static func locate(in directory: URL, fileManager: FileManager = .default) -> Result<Located, Failure> {
        let model = directory.appending(path: modelFileName)
        let voices = directory.appending(path: voicesFileName)
        for (url, name, expectedByteCount) in [(model, modelFileName, modelByteCount),
                                               (voices, voicesFileName, voicesByteCount)] {
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path(percentEncoded: false)),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let byteCount = attributes[.size] as? Int
            else { return .failure(.missing(name)) }
            guard byteCount == expectedByteCount else { return .failure(.sizeMismatch(name)) }
        }
        return .success(Located(model: model, voices: voices))
    }

    /// Hashes both files and compares them with the recorded digests. Hundreds of megabytes of I/O,
    /// so call it once when a resource directory is accepted, not on every render.
    public static func verify(_ located: Located) throws {
        for (url, name, expectedDigest) in [(located.model, modelFileName, modelSHA256),
                                            (located.voices, voicesFileName, voicesSHA256)] {
            guard try sha256Hex(of: url) == expectedDigest else { throw Failure.checksumMismatch(name) }
        }
    }

    static let hashChunkByteCount = 4 * 1024 * 1024

    /// Hashes a file in `hashChunkByteCount` chunks, so a 327 MB model never lands in memory as one
    /// `Data`. Internal rather than private: the tests hash a small file of their own through it.
    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: hashChunkByteCount), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The resource directory inside an app bundle. The app copies `App/Resources/Kokoro` in flat,
    /// so the model is found by name and its parent directory is what the engine wants.
    public static func bundled(in bundle: Bundle = .main) -> URL? {
        let name = URL(fileURLWithPath: modelFileName)
        return bundle.url(forResource: name.deletingPathExtension().lastPathComponent,
                          withExtension: name.pathExtension)?.deletingLastPathComponent()
    }

    /// Where the files sit when running from the repository rather than an app bundle: the checkout's
    /// `App/Resources/Kokoro`, or `T2S_KOKORO_RESOURCES` when it is set.
    public static var developmentDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["T2S_KOKORO_RESOURCES"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        // This file is <repo>/Packages/T2SKokoro/Sources/T2SKokoro/KokoroResources.swift.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 { root.deleteLastPathComponent() }
        return root.appending(path: "App/Resources/Kokoro", directoryHint: .isDirectory)
    }
}
