import Foundation
import SwiftData
import T2SCore

extension LibraryStore {
    /// A document's bookmarks, oldest first.
    public func bookmarks(for documentID: UUID) throws -> [Bookmark] {
        let descriptor = FetchDescriptor<StoredBookmark>(
            predicate: #Predicate { $0.documentID == documentID },
            sortBy: [SortDescriptor(\.createdAt)])
        return try modelContext.fetch(descriptor).map { row in
            Bookmark(id: row.id, documentID: row.documentID, position: row.position, note: row.note, createdAt: row.createdAt)
        }
    }

    /// Inserts, or replaces the bookmark with the same id.
    public func add(_ bookmark: Bookmark) throws {
        if let row = try bookmarkRow(bookmark.id) {
            row.documentID = bookmark.documentID
            row.href = bookmark.position.resourceHref
            row.progression = bookmark.position.progression
            row.charOffset = bookmark.position.charOffset
            row.cssSelector = bookmark.position.cssSelector
            row.note = bookmark.note
            row.createdAt = bookmark.createdAt
        } else {
            modelContext.insert(StoredBookmark(id: bookmark.id, documentID: bookmark.documentID, position: bookmark.position,
                                               note: bookmark.note, createdAt: bookmark.createdAt))
        }
        try commit()
    }

    public func deleteBookmark(id: UUID) throws {
        guard let row = try bookmarkRow(id) else { return }
        modelContext.delete(row)
        try commit()
    }

    func deleteBookmarks(for documentID: UUID) throws {
        let rows = try modelContext.fetch(FetchDescriptor<StoredBookmark>(predicate: #Predicate { $0.documentID == documentID }))
        for row in rows { modelContext.delete(row) }
    }

    private func bookmarkRow(_ id: UUID) throws -> StoredBookmark? {
        var descriptor = FetchDescriptor<StoredBookmark>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
