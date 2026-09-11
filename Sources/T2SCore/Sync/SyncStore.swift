// Sources/T2SCore/Sync/SyncStore.swift
import Foundation

/// What the engine needs from persistence, in domain terms (sync spec §4, §6). The engine decides;
/// the store records the decision. Implemented over the library in the app, in memory in tests.
public protocol SyncStore: Sendable {
    /// The local document with this key, as a record, or nil when unknown here.
    func syncedDocument(contentKey: String) async throws -> SyncedDocument?
    func syncedBookmark(id: UUID) async throws -> SyncedBookmark?
    /// Every local record changed since it was last pushed, deletion markers included.
    func dirtyRecords() async throws -> [SyncRecord]
    /// Upserts the document. Unknown here: inserted as a placeholder, `document.resume` becoming its
    /// position. Known: title, author, finished flag and clocks are written; the position is written
    /// only when `remote` is nil, else it is left alone and `remote` is stored as the pending offer.
    func write(_ document: SyncedDocument, offering remote: SyncedPosition?) async throws
    /// Upserts, or removes when `deletedAt` is set. Ignored when no local document has its key.
    func write(_ bookmark: SyncedBookmark) async throws
    /// A pulled deletion marker: the document, its files, chapters, audio and bookmarks go.
    func removeDocument(contentKey: String) async throws
    /// The records the provider accepted: dirty flags cleared, pushed markers dropped.
    func markClean(_ records: [SyncRecord]) async throws
}
