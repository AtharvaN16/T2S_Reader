import Foundation
import T2SCore

extension LibraryStore: PlayheadStore {
    /// `PlayheadStore` is fire-and-forget by contract: the coordinator saves on pause, seek, every
    /// utterance boundary, and finish, and cannot act on a failure. A throwing variant exists for
    /// callers that can (`savePosition`).
    public func save(_ playhead: SavedPlayhead, for documentID: UUID) async {
        try? savePosition(playhead, for: documentID)
    }

    /// Records the resume position, where it sits in time, and the last-played time (spec §3.2, §5).
    public func savePosition(_ playhead: SavedPlayhead, for documentID: UUID) throws {
        let row = try existing(documentID)
        Self.setResume(row, playhead)
        try touchPlayed(row)
    }

    /// A position without its time: the summary's elapsed time is nil until the next full save.
    public func savePosition(_ position: Position, for documentID: UUID) throws {
        let row = try existing(documentID)
        Self.setResume(row, position)
        try touchPlayed(row)
    }

    private func touchPlayed(_ row: StoredDocument) throws {
        let now = Date()
        row.lastPlayedAt = now
        row.updatedAt = now
        try commit()
    }
}
