import Foundation
import T2SCore

extension LibraryStore: PlayheadStore {
    /// `PlayheadStore` is fire-and-forget by contract: the coordinator saves on pause, seek, every
    /// utterance boundary, and finish, and cannot act on a failure. A throwing variant exists for
    /// callers that can (`savePosition`).
    public func save(_ position: Position, for documentID: UUID) async {
        try? savePosition(position, for: documentID)
    }

    /// Records the resume position and the last-played time (spec §3.2, §5).
    public func savePosition(_ position: Position, for documentID: UUID) throws {
        let row = try existing(documentID)
        Self.setResume(row, position)
        let now = Date()
        row.lastPlayedAt = now
        row.updatedAt = now
        try commit()
    }
}
