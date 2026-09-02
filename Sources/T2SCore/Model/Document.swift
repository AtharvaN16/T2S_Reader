import Foundation

public enum SourceType: String, Codable, Sendable {
    case epub, article, pdf
}

public struct Document: Codable, Hashable, Sendable, Identifiable {
    /// Client-generated; never a backend or CloudKit key (spec §3.7.1).
    public var id: UUID
    public var title: String
    public var author: String?
    public var sourceType: SourceType
    public var sourceURL: URL?
    /// Path relative to the app container.
    public var coverImagePath: String?
    public var addedAt: Date
    /// Per-document voice override.
    public var voiceID: String?
    public var resumePosition: Position?

    public init(id: UUID = UUID(), title: String, author: String? = nil, sourceType: SourceType,
                sourceURL: URL? = nil, coverImagePath: String? = nil, addedAt: Date = Date(),
                voiceID: String? = nil, resumePosition: Position? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.coverImagePath = coverImagePath
        self.addedAt = addedAt
        self.voiceID = voiceID
        self.resumePosition = resumePosition
    }
}
