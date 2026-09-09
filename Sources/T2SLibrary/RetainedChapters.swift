import Foundation
import T2SCore

/// The reader's output, kept beside the source (spec §5): a re-derivation after a segmenter or
/// normalizer bump starts from these blocks and never pays for Readium or PDFKit again (Plan 17,
/// audit §5.1). JSON, LZFSE-compressed — a novel's text is a megabyte or two.
enum RetainedChapters {
    static func write(_ chapters: [ChapterInput], to url: URL) throws {
        let json = try JSONEncoder().encode(chapters)
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        try compressed.write(to: url, options: .atomic)
    }

    /// nil when nothing was retained — a document imported before this build.
    static func read(from url: URL) throws -> [ChapterInput]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let compressed = try Data(contentsOf: url)
        let json = try (compressed as NSData).decompressed(using: .lzfse) as Data
        return try JSONDecoder().decode([ChapterInput].self, from: json)
    }
}
