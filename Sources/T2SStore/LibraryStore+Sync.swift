// Sources/T2SStore/LibraryStore+Sync.swift
import Foundation
import SwiftData
import T2SCore

/// The sync columns, in domain terms (sync spec §6). The engine decides, these record the decision;
/// `LibrarySyncStore` in T2SApp composes them with the library's file handling.
extension LibraryStore {
    static let documentTombstone = "document", bookmarkTombstone = "bookmark"

    public func syncedDocument(contentKey: String, deviceName: String) throws -> SyncedDocument? {
        try rowWithContentKey(contentKey).map { Self.synced($0, deviceName: deviceName) }
    }

    public func syncedBookmark(id: UUID) throws -> SyncedBookmark? {
        guard let row = try bookmarkRow(id), let key = try self.row(row.documentID)?.contentKey else { return nil }
        return Self.synced(row, contentKey: key)
    }

    /// Dirty documents, dirty bookmarks, then the markers — documents first so a receiver can
    /// insert a placeholder before its bookmarks arrive.
    public func dirtyRecords(deviceName: String) throws -> [SyncRecord] {
        var records: [SyncRecord] = []
        let documents = try modelContext.fetch(FetchDescriptor<StoredDocument>(predicate: #Predicate { $0.isDirty }))
        // One record per content key, the newer row winning: two local rows can only share a key
        // through a duplicate import made before that was refused (`ImportError.alreadyInLibrary`),
        // and pushing both would have them overwrite each other, cycle after cycle.
        var byContentKey: [String: SyncedDocument] = [:]
        for row in documents where row.contentKey != nil {
            let d = Self.synced(row, deviceName: deviceName)
            if let held = byContentKey[d.contentKey], held.updatedAt >= d.updatedAt { continue }
            byContentKey[d.contentKey] = d
        }
        records.append(contentsOf: byContentKey.values.sorted { $0.contentKey < $1.contentKey }.map(SyncRecord.document))
        let bookmarks = try modelContext.fetch(FetchDescriptor<StoredBookmark>(predicate: #Predicate { $0.isDirty }))
        for row in bookmarks {
            if let key = try self.row(row.documentID)?.contentKey { records.append(.bookmark(Self.synced(row, contentKey: key))) }
        }
        for stone in try modelContext.fetch(FetchDescriptor<StoredTombstone>()) {
            if stone.kind == Self.documentTombstone {
                records.append(.document(SyncedDocument(contentKey: stone.key, title: "", sourceType: .epub, addedAt: stone.deletedAt,
                                                        updatedAt: stone.deletedAt, deletedAt: stone.deletedAt)))
            } else if let id = UUID(uuidString: stone.key) {
                records.append(.bookmark(SyncedBookmark(id: id, contentKey: "", position: Position(resourceHref: "", progression: 0),
                                                        createdAt: stone.deletedAt, updatedAt: stone.deletedAt, deletedAt: stone.deletedAt)))
            }
        }
        return records
    }

    /// Upserts a pulled document (sync spec §4, §6): a known row — placeholder or not — gets an
    /// offer, never a moved position; only a document with no row of its own yet (the `else` below)
    /// takes one directly. Never touches `isDirty`: only `markClean` after a successful push clears
    /// it, so a row that keeps a newer local position (a resume the offer left alone) stays queued
    /// for the next push.
    public func writeSynced(_ document: SyncedDocument, offering remote: SyncedPosition?) throws {
        if let row = try rowWithContentKey(document.contentKey) {
            row.title = document.title
            row.author = document.author
            row.isFinished = document.isFinished
            row.updatedAt = document.updatedAt
            if let remote {
                row.pendingRemoteHref = remote.position.resourceHref
                row.pendingRemoteProgression = remote.position.progression
                row.pendingRemoteCharOffset = remote.position.charOffset
                row.pendingRemoteCSSSelector = remote.position.cssSelector
                row.pendingRemoteSavedAt = remote.savedAt
                row.pendingRemoteDevice = remote.deviceName
            } else if let resume = document.resume, resume.savedAt != row.resumeSavedAt {
                // A placeholder has no reading of its own: its record's own resume moves the
                // position directly, since nothing local is offered against.
                Self.setResume(row, resume.position)
                row.resumeSavedAt = resume.savedAt
                row.resumeDevice = resume.deviceName
            }
        } else {
            let row = StoredDocument(id: UUID(), title: document.title, author: document.author, sourceType: document.sourceType.rawValue,
                                     sourceURL: document.sourceURL?.absoluteString, coverImagePath: nil, addedAt: document.addedAt, voiceID: nil,
                                     schemaVersion: Versions.schema, segmenterVersion: 0, normalizerVersion: 0)
            row.contentKey = document.contentKey
            row.isPlaceholder = true
            row.isFinished = document.isFinished
            row.updatedAt = document.updatedAt
            if let resume = document.resume {
                Self.setResume(row, resume.position)
                row.resumeSavedAt = resume.savedAt
                row.resumeDevice = resume.deviceName
            }
            modelContext.insert(row)
        }
        try commit()
    }

    /// Upserts a pulled bookmark, or removes it when `deletedAt` is set; an upsert is ignored when no
    /// local document has its key. Never touches `isDirty`: only `markClean` after a successful push
    /// clears it.
    ///
    /// The deletion comes first, before the document is looked up at all: a marker is built from the
    /// tombstone row, which keeps only the bookmark's uuid, so its `contentKey` is empty by
    /// construction (`dirtyRecords` above) and no document could ever match it. Guarding the marker
    /// on a document row dropped every pulled deletion, and the bookmark came back on the next pull.
    public func writeSynced(_ bookmark: SyncedBookmark) throws {
        if bookmark.deletedAt != nil {
            if let row = try bookmarkRow(bookmark.id) { modelContext.delete(row) }
            try commit()
            return
        }
        guard let document = try rowWithContentKey(bookmark.contentKey) else { return }
        if let row = try bookmarkRow(bookmark.id) {
            row.href = bookmark.position.resourceHref; row.progression = bookmark.position.progression
            row.charOffset = bookmark.position.charOffset; row.cssSelector = bookmark.position.cssSelector
            row.note = bookmark.note; row.userNote = bookmark.userNote; row.updatedAt = bookmark.updatedAt
        } else {
            let row = StoredBookmark(id: bookmark.id, documentID: document.id, position: bookmark.position, note: bookmark.note, createdAt: bookmark.createdAt)
            row.userNote = bookmark.userNote
            row.updatedAt = bookmark.updatedAt
            modelContext.insert(row)
        }
        try commit()
    }

    /// The local document with this key, for the adapter that removes a pulled deletion's document
    /// through the library (files and audio included). nil when nothing has the key.
    public func documentID(contentKey: String) throws -> UUID? { try rowWithContentKey(contentKey)?.id }

    /// Clears the dirty flags of what the server accepted. A row only loses its flag when it still
    /// says what the pushed record said: a position saved while the push was in flight leaves the row
    /// newer than the record, and it stays dirty so the next cycle carries it (sync spec §6).
    public func markClean(_ records: [SyncRecord]) throws {
        for record in records {
            switch record {
            case .document(let d) where d.deletedAt != nil: try removeTombstone(kind: Self.documentTombstone, key: d.contentKey)
            case .document(let d):
                if let row = try rowWithContentKey(d.contentKey), row.updatedAt <= d.updatedAt { row.isDirty = false }
            case .bookmark(let b) where b.deletedAt != nil: try removeTombstone(kind: Self.bookmarkTombstone, key: b.id.uuidString)
            case .bookmark(let b):
                if let row = try bookmarkRow(b.id), (row.updatedAt ?? row.createdAt) <= b.updatedAt { row.isDirty = false }
            }
        }
        try commit()
    }

    public func placeholder(contentKey: String) throws -> UUID? {
        guard let row = try rowWithContentKey(contentKey), row.isPlaceholder else { return nil }
        return row.id
    }

    public func setContentKey(_ id: UUID, _ key: String) throws {
        let row = try existing(id)
        row.contentKey = key
        row.isDirty = true
        try commit()
    }

    /// The real document lands in the placeholder's row: chapters, cover and versions from the
    /// import, everything sync brought — position, pending offer, bookmarks — kept (sync spec §5).
    public func fill(placeholder id: UUID, with document: Document, timeline: Timeline) throws {
        let row = try existing(id)
        row.title = document.title
        row.author = document.author
        row.coverImagePath = document.coverImagePath
        row.sourceType = document.sourceType.rawValue
        row.isPlaceholder = false
        row.updatedAt = Date()
        row.isDirty = true
        try replaceChapters(of: row, with: timeline)
        if row.queueOrder == nil { try enqueue(row) }
        try commit()
        // The row stopped being a placeholder and carries the real book's title and chapters: the
        // other devices are told, like every other write a reader made (sync spec §7).
        noteLocalChange()
    }

    public func pendingRemotePosition(for id: UUID) throws -> SyncedPosition? {
        let row = try existing(id)
        guard let href = row.pendingRemoteHref, let savedAt = row.pendingRemoteSavedAt else { return nil }
        return SyncedPosition(position: Position(resourceHref: href, progression: row.pendingRemoteProgression ?? 0,
                                                 charOffset: row.pendingRemoteCharOffset, cssSelector: row.pendingRemoteCSSSelector),
                              savedAt: savedAt, deviceName: row.pendingRemoteDevice ?? "another device")
    }

    public func clearPendingRemotePosition(for id: UUID) throws {
        let row = try existing(id)
        row.pendingRemoteHref = nil; row.pendingRemoteProgression = nil; row.pendingRemoteCharOffset = nil
        row.pendingRemoteCSSSelector = nil; row.pendingRemoteSavedAt = nil; row.pendingRemoteDevice = nil
        try commit()
    }

    public func documentsMissingContentKey() throws -> [Document] {
        try modelContext.fetch(FetchDescriptor<StoredDocument>(predicate: #Predicate { $0.contentKey == nil })).map(Self.domain)
    }

    // MARK: helpers

    /// Posted after every write a reader made that sync should carry (`noteLocalChange()`); the
    /// app's `SyncModel` syncs two seconds after the last one (sync spec §7).
    public nonisolated static let localChangeNotification = Notification.Name("LibraryStore.localChange")
    func noteLocalChange() { NotificationCenter.default.post(name: Self.localChangeNotification, object: nil) }

    func rowWithContentKey(_ key: String) throws -> StoredDocument? {
        var descriptor = FetchDescriptor<StoredDocument>(predicate: #Predicate { $0.contentKey == key })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func addTombstone(kind: String, key: String) {
        modelContext.insert(StoredTombstone(kind: kind, key: key, deletedAt: Date()))
    }

    private func removeTombstone(kind: String, key: String) throws {
        for stone in try modelContext.fetch(FetchDescriptor<StoredTombstone>(predicate: #Predicate { $0.kind == kind && $0.key == key })) {
            modelContext.delete(stone)
        }
    }

    static func synced(_ r: StoredDocument, deviceName: String) -> SyncedDocument {
        let resume = r.resumeHref.map { href in
            SyncedPosition(position: Position(resourceHref: href, progression: r.resumeProgression ?? 0, charOffset: r.resumeCharOffset, cssSelector: r.resumeCSSSelector),
                           savedAt: r.resumeSavedAt ?? r.updatedAt, deviceName: r.resumeDevice ?? deviceName)
        }
        return SyncedDocument(contentKey: r.contentKey ?? "", title: r.title, author: r.author, sourceType: SourceType(rawValue: r.sourceType) ?? .epub,
                              sourceURL: r.sourceURL.flatMap(URL.init(string:)), addedAt: r.addedAt, isFinished: r.isFinished,
                              resume: resume, updatedAt: r.updatedAt)
    }

    static func synced(_ r: StoredBookmark, contentKey: String) -> SyncedBookmark {
        SyncedBookmark(id: r.id, contentKey: contentKey, position: r.position, note: r.note, userNote: r.userNote,
                       createdAt: r.createdAt, updatedAt: r.updatedAt ?? r.createdAt)
    }
}
