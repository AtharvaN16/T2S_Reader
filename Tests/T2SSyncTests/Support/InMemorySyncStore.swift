// Tests/T2SSyncTests/Support/InMemorySyncStore.swift
import Foundation
import T2SCore

/// One device's persistence, in memory: the same contract `LibrarySyncStore` keeps over the
/// library, plus the local edits the scenarios need.
actor InMemorySyncStore: SyncStore {
    var documents: [String: SyncedDocument] = [:]
    var pending: [String: SyncedPosition] = [:]
    var placeholders: Set<String> = []
    var bookmarks: [UUID: SyncedBookmark] = [:]
    var dirty: Set<String> = []
    var tombstones: [SyncRecord] = []
    var removed: [String] = []

    // MARK: SyncStore
    func syncedDocument(contentKey: String) -> SyncedDocument? { documents[contentKey] }
    func syncedBookmark(id: UUID) -> SyncedBookmark? { bookmarks[id] }
    func dirtyRecords() -> [SyncRecord] {
        documents.values.filter { dirty.contains("doc:\($0.contentKey)") }.sorted { $0.contentKey < $1.contentKey }.map(SyncRecord.document)
            + bookmarks.values.filter { dirty.contains("bm:\($0.id)") }.sorted { $0.updatedAt < $1.updatedAt }.map(SyncRecord.bookmark)
            + tombstones
    }
    func write(_ document: SyncedDocument, offering remote: SyncedPosition?) {
        if var local = documents[document.contentKey] {
            local.title = document.title; local.author = document.author; local.isFinished = document.isFinished; local.updatedAt = document.updatedAt
            if let remote { pending[document.contentKey] = remote }
            else { local.resume = document.resume }
            documents[document.contentKey] = local
        } else {
            documents[document.contentKey] = document
            placeholders.insert(document.contentKey)
        }
    }
    /// Like `LibraryStore.writeSynced(_ bookmark:)`: a deletion marker carries no content key, so it
    /// is applied before the document is looked up at all — guarding it on a document would drop
    /// every pulled deletion.
    func write(_ bookmark: SyncedBookmark) {
        if bookmark.deletedAt != nil { bookmarks[bookmark.id] = nil; return }
        guard documents[bookmark.contentKey] != nil else { return }
        bookmarks[bookmark.id] = bookmark
    }
    func removeDocument(contentKey: String) {
        documents[contentKey] = nil; pending[contentKey] = nil; placeholders.remove(contentKey)
        bookmarks = bookmarks.filter { $0.value.contentKey != contentKey }
        removed.append(contentKey)
    }
    /// Like `LibraryStore.markClean`: a row edited while the push was in flight is newer than the
    /// record that was accepted, and keeps its flag for the next cycle.
    func markClean(_ records: [SyncRecord]) {
        for record in records {
            switch record {
            case .document(let d):
                if let local = documents[d.contentKey], local.updatedAt <= d.updatedAt { dirty.remove("doc:\(d.contentKey)") }
                tombstones.removeAll { $0 == record }
            case .bookmark(let b):
                if let local = bookmarks[b.id], local.updatedAt <= b.updatedAt { dirty.remove("bm:\(b.id)") }
                tombstones.removeAll { $0 == record }
            }
        }
    }

    // MARK: what a reader does on this device
    func importLocal(_ key: String, title: String, at time: Date) {
        documents[key] = SyncedDocument(contentKey: key, title: title, sourceType: .epub, addedAt: time, updatedAt: time)
        dirty.insert("doc:\(key)")
    }
    func fillPlaceholder(_ key: String) { placeholders.remove(key) }
    func savePosition(_ key: String, _ progression: Double, at time: Date, device: String) {
        documents[key]?.resume = SyncedPosition(position: Position(resourceHref: "c1", progression: progression), savedAt: time, deviceName: device)
        documents[key]?.updatedAt = time
        dirty.insert("doc:\(key)")
    }
    func acceptOffer(_ key: String, at time: Date, device: String) {
        guard let offer = pending[key] else { return }
        documents[key]?.resume = SyncedPosition(position: offer.position, savedAt: time, deviceName: device)
        documents[key]?.updatedAt = time
        pending[key] = nil
        dirty.insert("doc:\(key)")
    }
    func addBookmark(_ id: UUID, _ key: String, note: String?, at time: Date) {
        bookmarks[id] = SyncedBookmark(id: id, contentKey: key, position: Position(resourceHref: "c1", progression: 0.2), note: note, createdAt: time, updatedAt: time)
        dirty.insert("bm:\(id)")
    }
    func editBookmark(_ id: UUID, note: String, at time: Date) {
        bookmarks[id]?.note = note; bookmarks[id]?.updatedAt = time
        dirty.insert("bm:\(id)")
    }
    func deleteBookmark(_ id: UUID, at time: Date) {
        guard let b = bookmarks.removeValue(forKey: id) else { return }
        // `contentKey: ""`, exactly as `LibraryStore.dirtyRecords` builds it: the tombstone row keeps
        // only the uuid, and the scenarios must exercise the contract the real store keeps.
        tombstones.append(.bookmark(SyncedBookmark(id: id, contentKey: "", position: b.position, createdAt: b.createdAt, updatedAt: time, deletedAt: time)))
    }
    func deleteEverywhere(_ key: String, at time: Date) {
        documents[key] = nil
        tombstones.append(.document(SyncedDocument(contentKey: key, title: "", sourceType: .epub, addedAt: time, updatedAt: time, deletedAt: time)))
    }
}
