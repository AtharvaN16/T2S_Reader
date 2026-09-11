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
    /// `ContentKey` (sync spec §2); nil for a document sync has not keyed yet, or one with no file
    /// and no URL, which never syncs.
    public var contentKey: String?
    /// A document another device has that this one has no file for (sync spec §5).
    public var isPlaceholder: Bool

    public init(id: UUID = UUID(), title: String, author: String? = nil, sourceType: SourceType,
                sourceURL: URL? = nil, coverImagePath: String? = nil, addedAt: Date = Date(),
                voiceID: String? = nil, resumePosition: Position? = nil,
                contentKey: String? = nil, isPlaceholder: Bool = false) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.coverImagePath = coverImagePath
        self.addedAt = addedAt
        self.voiceID = voiceID
        self.resumePosition = resumePosition
        self.contentKey = contentKey
        self.isPlaceholder = isPlaceholder
    }
}

extension Document {
    /// The author as a screen should print it: the same name twice is one name. EPUBs routinely
    /// carry `dc:creator` more than once — the plain name and the role-tagged one — and joining
    /// them gave "Jane Austen, Jane Austen" (owner, 2026-09-11). Applied on the way out as well as
    /// at import, so books already on the shelf read right without being imported again.
    public var displayAuthor: String? { author.flatMap { AuthorNames.collapse($0) } }
}

/// One author line out of however many names a file lists.
public enum AuthorNames {
    /// Trims, drops blanks and repeats (ignoring case), and rejoins with ", "; nil when nothing is
    /// left. Order is the file's: the first spelling of a name is the one kept.
    public static func collapse(_ author: String) -> String? {
        var seen = Set<String>()
        let names = author
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// The same rule over names that have not been joined yet (the importers' path).
    public static func collapse(_ names: [String]) -> String? {
        collapse(names.joined(separator: ", "))
    }
}
