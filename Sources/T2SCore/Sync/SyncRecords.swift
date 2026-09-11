// Sources/T2SCore/Sync/SyncRecords.swift
import Foundation

/// A reading position as one device saved it (sync spec §3): where, when, and on what, so the other
/// device can offer "Continue from iPhone" rather than move the playhead.
public struct SyncedPosition: Sendable, Codable, Hashable {
    public var position: Position
    public var savedAt: Date
    public var deviceName: String
    public init(position: Position, savedAt: Date, deviceName: String) {
        self.position = position; self.savedAt = savedAt; self.deviceName = deviceName
    }
}

/// One document's sync record: the list entry, its position, and its deletion marker. Never the
/// file, never the chapters (sync spec §1). Keyed by `contentKey` (sync spec §2).
public struct SyncedDocument: Sendable, Codable, Hashable {
    public var contentKey: String
    public var title: String
    public var author: String?
    public var sourceType: SourceType
    public var sourceURL: URL?
    public var addedAt: Date
    public var isFinished: Bool
    public var resume: SyncedPosition?
    /// The record's own clock: the newer wins (sync spec §4).
    public var updatedAt: Date
    /// A marker, not a removal: the record stays so the deletion reaches every device.
    public var deletedAt: Date?
    public init(contentKey: String, title: String, author: String? = nil, sourceType: SourceType, sourceURL: URL? = nil,
                addedAt: Date, isFinished: Bool = false, resume: SyncedPosition? = nil, updatedAt: Date, deletedAt: Date? = nil) {
        self.contentKey = contentKey; self.title = title; self.author = author; self.sourceType = sourceType
        self.sourceURL = sourceURL; self.addedAt = addedAt; self.isFinished = isFinished; self.resume = resume
        self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct SyncedBookmark: Sendable, Codable, Hashable {
    public var id: UUID
    public var contentKey: String
    public var position: Position
    /// The passage the app captured. Named `note` because that is this record's CloudKit key and
    /// has been since iCloud sync shipped; it must never be reused for the reader's writing.
    public var note: String?
    /// The reader's own note. Absent from records written by a build older than 2026-09-11.
    public var userNote: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public init(id: UUID, contentKey: String, position: Position, note: String? = nil, userNote: String? = nil,
                createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id; self.contentKey = contentKey; self.position = position; self.note = note
        self.userNote = userNote; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public enum SyncRecord: Sendable, Hashable {
    case document(SyncedDocument)
    case bookmark(SyncedBookmark)

    /// The newer of two clocks is what the merge compares (sync spec §4).
    public var updatedAt: Date {
        switch self {
        case .document(let d): return d.updatedAt
        case .bookmark(let b): return b.updatedAt
        }
    }
}
