import Foundation

/// A user-placed anchor into a document (spec §2.2). Persisted as a `Position`, never as a
/// runtime index (spec §3.2).
///
/// Two strings, and they must never be conflated. `passageText` is the utterance's source, written
/// by the app at save so the bookmark keeps its words when the document is re-derived and utterance
/// indices move. `userNote` is the reader's own writing, and is absent on most bookmarks.
public struct Bookmark: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var documentID: UUID
    public var position: Position
    /// Written by the app, never edited. Stored in the column still called `note` (2026-09-11 spec
    /// §3: that column's meaning is already in iCloud and can never be reused).
    public var passageText: String?
    /// Written by the reader, edited freely, nil when they have written nothing.
    public var userNote: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), documentID: UUID, position: Position, passageText: String? = nil,
                userNote: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.documentID = documentID
        self.position = position
        self.passageText = passageText
        self.userNote = userNote
        self.createdAt = createdAt
    }
}
