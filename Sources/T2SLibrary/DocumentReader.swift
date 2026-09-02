import Foundation
import T2SCore

/// What a reader extracts from one source file: metadata, a cover, and chapters of blocks ready
/// for `TimelineBuilder` (spec §4).
public struct ReadDocument: Hashable, Sendable {
    public var title: String
    public var author: String?
    /// Encoded image bytes (JPEG or PNG); nil when the source has no cover.
    public var coverImage: Data?
    public var chapters: [ChapterInput]
    /// Resources (hrefs or page labels) that yielded no text or failed to parse — imported
    /// documents say what was skipped rather than failing silently (spec §6).
    public var skippedResources: [String]

    public init(title: String, author: String? = nil, coverImage: Data? = nil,
                chapters: [ChapterInput], skippedResources: [String] = []) {
        self.title = title
        self.author = author
        self.coverImage = coverImage
        self.chapters = chapters
        self.skippedResources = skippedResources
    }
}

/// Turns a source file into chapters of `SourceBlock`s with the `Position` semantics fixed in the
/// plan's Global Constraints. Implementations: `PDFDocumentReader` (here) and
/// `ReadiumDocumentReader` (Packages/T2SReadium; EPUB and article EPUB).
public protocol DocumentReader: Sendable {
    var supportedTypes: Set<SourceType> { get }
    func read(fileURL: URL, sourceType: SourceType) async throws -> ReadDocument
}
