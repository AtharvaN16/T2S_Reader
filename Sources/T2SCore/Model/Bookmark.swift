import Foundation

/// A user-placed anchor into a document (spec §2.2). Persisted as a `Position`, never as a
/// runtime index (spec §3.2).
public struct Bookmark: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var documentID: UUID
    public var position: Position
    public var note: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), documentID: UUID, position: Position, note: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.documentID = documentID
        self.position = position
        self.note = note
        self.createdAt = createdAt
    }
}
