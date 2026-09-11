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
    public init(library: Library, deviceName: String) { self.library = library; self.deviceName = deviceName }

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
        try await library.delete(id, everywhere: false)             // it came from the other device: no marker of our own
    }
    public func markClean(_ records: [SyncRecord]) async throws { try await library.store.markClean(records) }
}
