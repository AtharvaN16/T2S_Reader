import Foundation
import Testing
import T2SCore
@testable import T2SStore

@Suite struct BookmarkTests {
    @Test func addListDeleteInCreationOrder() async throws {
        let store = try LibraryStore.inMemory()
        let doc = Document(title: "D", sourceType: .epub)
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let b1 = Bookmark(documentID: doc.id, position: Position(resourceHref: "ch1.xhtml", progression: 0.1), passageText: "first", createdAt: t0)
        let b2 = Bookmark(documentID: doc.id, position: Position(resourceHref: "ch1.xhtml", progression: 0.9), createdAt: t0.addingTimeInterval(1))
        try await store.add(b2)
        try await store.add(b1)
        #expect(try await store.bookmarks(for: doc.id) == [b1, b2])
        var edited = b1
        edited.passageText = "renamed"
        try await store.add(edited)                                        // upsert by id
        #expect(try await store.bookmarks(for: doc.id) == [edited, b2])
        try await store.deleteBookmark(id: b2.id)
        #expect(try await store.bookmarks(for: doc.id) == [edited])
        #expect(try await store.bookmarks(for: UUID()).isEmpty)
    }

    @Test func deletingTheDocumentDeletesItsBookmarks() async throws {
        let store = try LibraryStore.inMemory()
        let doc = Document(title: "D", sourceType: .epub)
        let other = Document(title: "O", sourceType: .pdf)
        for d in [doc, other] { try await store.insert(d, timeline: makeTimeline([[makeUtterance("One.")]])) }
        try await store.add(Bookmark(documentID: doc.id, position: Position(resourceHref: "ch1.xhtml", progression: 0)))
        let kept = Bookmark(documentID: other.id, position: Position(resourceHref: "source.pdf", progression: 0))
        try await store.add(kept)
        try await store.delete(id: doc.id)
        #expect(try await store.bookmarks(for: doc.id).isEmpty)
        #expect(try await store.bookmarks(for: other.id) == [kept])
    }

    @Test func userNoteRoundTripsBesideThePassage() async throws {
        // Exactly representable as a Double, so it survives the SQLite round trip unchanged
        // (same fixed instant `LibraryStoreTests` uses, which is scoped to that suite).
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let store = try LibraryStore.inMemory()
        let doc = Document(title: "D", sourceType: .epub)
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        let saved = Bookmark(documentID: doc.id, position: Position(resourceHref: "ch1.xhtml", progression: 0.1),
                             passageText: "The passage the app captured.", createdAt: fixedDate)
        try await store.add(saved)
        #expect(try await store.bookmarks(for: doc.id) == [saved])

        var annotated = saved
        annotated.userNote = "my own words"
        try await store.add(annotated)
        let read = try #require(try await store.bookmarks(for: doc.id).first)
        #expect(read.userNote == "my own words")
        #expect(read.passageText == "The passage the app captured.")

        annotated.userNote = nil
        try await store.add(annotated)
        #expect(try await store.bookmarks(for: doc.id).first?.userNote == nil)
    }
}
