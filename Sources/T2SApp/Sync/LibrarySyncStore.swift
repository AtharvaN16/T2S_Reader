// Sources/T2SApp/Sync/LibrarySyncStore.swift
import Foundation
import T2SCore
import T2SLibrary
import T2SStore

/// `SyncStore` over the library (sync spec §6): the store's primitives, plus the library for what
/// touches files — a pulled deletion removes the document the way a reader's delete does.
public actor LibrarySyncStore: SyncStore {
    private let library: Library
    private let deviceName: String
    /// Awaited before a pulled deletion removes the document: the app unloads the player when it is
    /// holding that very book, so nothing keeps sounding from — or saving a position into — a row
    /// that is about to be gone. nil in tests and in any build that plays nothing.
    public private(set) var onRemove: (@Sendable (UUID) async -> Void)?
    public init(library: Library, deviceName: String) { self.library = library; self.deviceName = deviceName }

    public func setOnRemove(_ handler: (@Sendable (UUID) async -> Void)?) { onRemove = handler }

    public func syncedDocument(contentKey: String) async throws -> SyncedDocument? {
        try await library.store.syncedDocument(contentKey: contentKey, deviceName: deviceName)
    }
    public func syncedBookmark(id: UUID) async throws -> SyncedBookmark? { try await library.store.syncedBookmark(id: id) }
    public func dirtyRecords() async throws -> [SyncRecord] { try await library.store.dirtyRecords(deviceName: deviceName) }
    public func write(_ document: SyncedDocument, offering remote: SyncedPosition?) async throws {
        try await library.store.writeSynced(document, offering: remote)
    }
    public func write(_ bookmark: SyncedBookmark) async throws { try await library.store.writeSynced(bookmark) }
    public func removeDocument(contentKey: String) async throws {
        guard let id = try await library.store.documentID(contentKey: contentKey) else { return }
        await onRemove?(id)                                         // the player lets go before the row and its audio do
        try await library.delete(id, everywhere: false)             // it came from the other device: no marker of our own
    }
    public func markClean(_ records: [SyncRecord]) async throws { try await library.store.markClean(records) }
}
