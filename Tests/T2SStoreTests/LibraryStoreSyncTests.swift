import Foundation
import SwiftData
import Testing
import T2SCore
@testable import T2SStore

/// `.serialized`: these tests, run concurrently against each other, intermittently cross-talk
/// through SwiftData's in-memory containers (the same flakiness `HTTPVoiceEngineTests` and
/// `RoutedEngineTests` serialize against, for a different shared resource).
@Suite(.serialized) struct LibraryStoreSyncTests {
    private func store() throws -> LibraryStore { try LibraryStore.inMemory() }
    /// `makeTimeline` and `makeUtterance` are the module-internal helpers in
    /// `Tests/T2SStoreTests/Support/Fixtures.swift`, shared across this test target.
    private func timeline() -> Timeline { makeTimeline([[makeUtterance("Hello.")]]) }
    private func document(_ key: String) -> Document {
        Document(title: "A Book", sourceType: .epub, addedAt: Date(timeIntervalSince1970: 1000), contentKey: key)
    }

    /// A position save, a bookmark, a finish flag: each leaves its row dirty, and the dirty records
    /// carry this device's name and the save time. Marking clean clears them.
    @Test func writesLeaveRowsDirtyUntilMarkedClean() async throws {
        let s = try store()
        let doc = document("sha256:aaa")
        try await s.insert(doc, timeline: timeline())
        try await s.markClean(try await s.dirtyRecords(deviceName: "iPhone"))    // the import itself is dirty
        #expect(try await s.dirtyRecords(deviceName: "iPhone").isEmpty)

        try await s.savePosition(Position(resourceHref: "c1.xhtml", progression: 0.5), for: doc.id)
        let bookmark = Bookmark(documentID: doc.id, position: Position(resourceHref: "c1.xhtml", progression: 0.2), note: "here")
        try await s.add(bookmark)
        let dirty = try await s.dirtyRecords(deviceName: "iPhone")
        #expect(dirty.count == 2)
        guard case .document(let d) = dirty[0], case .bookmark(let b) = dirty[1] else { Issue.record("wrong kinds \(dirty)"); return }
        #expect(d.contentKey == "sha256:aaa")
        #expect(d.resume?.deviceName == "iPhone")
        #expect(d.resume?.position.progression == 0.5)
        #expect(b.id == bookmark.id && b.contentKey == "sha256:aaa" && b.note == "here")

        try await s.markClean(dirty)
        #expect(try await s.dirtyRecords(deviceName: "iPhone").isEmpty)
        try await s.deleteBookmark(id: bookmark.id)
        let afterDelete = try await s.dirtyRecords(deviceName: "iPhone")
        #expect(afterDelete.count == 1)
        guard case .bookmark(let gone) = afterDelete[0] else { Issue.record("expected a bookmark marker"); return }
        #expect(gone.id == bookmark.id && gone.deletedAt != nil)
    }

    /// A pulled document with no local match is a placeholder that carries the position; the same
    /// key pulled again with an offer leaves the local position alone and stores the offer.
    @Test func aPulledDocumentIsAPlaceholderAndAnOfferNeverMovesThePosition() async throws {
        let s = try store()
        let remote = SyncedDocument(contentKey: "url:https://x.y/a", title: "Article", sourceType: .article,
                                    sourceURL: URL(string: "https://x.y/a"), addedAt: Date(timeIntervalSince1970: 5),
                                    resume: SyncedPosition(position: Position(resourceHref: "c1.xhtml", progression: 0.3),
                                                           savedAt: Date(timeIntervalSince1970: 50), deviceName: "iPad"),
                                    updatedAt: Date(timeIntervalSince1970: 50))
        try await s.writeSynced(remote, offering: nil)
        let id = try #require(try await s.placeholder(contentKey: "url:https://x.y/a"))
        let stored = try #require(try await s.document(id: id))
        #expect(stored.isPlaceholder && stored.resumePosition?.progression == 0.3)
        #expect(try await s.summary(id: id)?.remoteDeviceName == "iPad")

        let offer = SyncedPosition(position: Position(resourceHref: "c1.xhtml", progression: 0.8),
                                   savedAt: Date(timeIntervalSince1970: 90), deviceName: "iPad")
        try await s.writeSynced(remote, offering: offer)
        #expect(try await s.document(id: id)?.resumePosition?.progression == 0.3)
        #expect(try await s.pendingRemotePosition(for: id) == offer)
        try await s.clearPendingRemotePosition(for: id)
        #expect(try await s.pendingRemotePosition(for: id) == nil)
    }

    /// Filling a placeholder with the real book keeps its position and bookmarks and ends the
    /// placeholder state; deleting everywhere leaves a marker behind.
    @Test func fillingAPlaceholderKeepsWhatSyncBroughtAndDeleteEverywhereLeavesAMarker() async throws {
        let s = try store()
        let remote = SyncedDocument(contentKey: "sha256:bbb", title: "Book", sourceType: .epub, addedAt: Date(timeIntervalSince1970: 5),
                                    resume: SyncedPosition(position: Position(resourceHref: "c1.xhtml", progression: 0.4),
                                                           savedAt: Date(timeIntervalSince1970: 50), deviceName: "iPad"),
                                    updatedAt: Date(timeIntervalSince1970: 50))
        try await s.writeSynced(remote, offering: nil)
        let id = try #require(try await s.placeholder(contentKey: "sha256:bbb"))
        try await s.writeSynced(SyncedBookmark(id: UUID(), contentKey: "sha256:bbb", position: Position(resourceHref: "c1.xhtml", progression: 0.1),
                                               createdAt: Date(timeIntervalSince1970: 20), updatedAt: Date(timeIntervalSince1970: 20)))
        try await s.fill(placeholder: id, with: Document(id: id, title: "Book, really", sourceType: .epub, contentKey: "sha256:bbb"), timeline: timeline())
        let filled = try #require(try await s.document(id: id))
        #expect(!filled.isPlaceholder && filled.title == "Book, really" && filled.resumePosition?.progression == 0.4)
        #expect(try await s.bookmarks(for: id).count == 1)
        #expect(try await s.placeholder(contentKey: "sha256:bbb") == nil)

        try await s.delete(id: id, recordingDeletion: true)
        let dirty = try await s.dirtyRecords(deviceName: "iPhone")
        #expect(dirty.count == 1)
        guard case .document(let marker) = dirty[0] else { Issue.record("expected a document marker"); return }
        #expect(marker.contentKey == "sha256:bbb" && marker.deletedAt != nil)
        #expect(try await s.documentID(contentKey: "sha256:bbb") == nil)
    }

    /// The riskiest line of the change: a store written by the app as it ships today (schema V2)
    /// opens under V3 with the new columns nil or false and nothing lost.
    @Test func aV2StoreOpensUnderV3() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "v2-\(UUID().uuidString)").appending(path: "Library.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let id = UUID()
        do {
            let v2 = try ModelContainer(for: Schema(versionedSchema: LibrarySchemaV2.self), configurations: ModelConfiguration(url: url))
            let context = ModelContext(v2)
            context.insert(LibrarySchemaV2.StoredDocument(id: id, title: "Old", author: nil, sourceType: "epub", sourceURL: nil, coverImagePath: nil,
                                                          addedAt: Date(timeIntervalSince1970: 1), voiceID: nil, schemaVersion: 1, segmenterVersion: 2, normalizerVersion: 4))
            try context.save()
        }
        let s = try LibraryStore.onDisk(at: url)
        let document = try #require(try await s.document(id: id))
        #expect(document.title == "Old" && document.contentKey == nil && !document.isPlaceholder)
        #expect(try await s.dirtyRecords(deviceName: "iPhone").isEmpty)
        #expect(try await s.documentsMissingContentKey().map(\.id) == [id])
    }
}
