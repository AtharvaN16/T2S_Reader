import Foundation
import Testing
import T2SCore
@testable import T2SStore

@Suite struct PlayheadStoreTests {
    @Test func saveThroughTheProtocolPersistsPositionAndLastPlayed() async throws {
        let store = try LibraryStore.inMemory()
        let doc = Document(title: "D", sourceType: .epub, addedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        let playhead: any PlayheadStore = store
        let p = Position(resourceHref: "ch1.xhtml", progression: 0.25, charOffset: 12, cssSelector: "p:nth-child(3)")
        await playhead.save(SavedPlayhead(position: p, chapterIndex: 0, secondsIntoChapter: 0.5), for: doc.id)
        #expect(try await store.document(id: doc.id)?.resumePosition == p)
        let s = try #require(try await store.summary(id: doc.id))
        #expect(s.lastPlayedAt != nil)
        #expect(abs((s.lastPlayedAt ?? .distantPast).timeIntervalSinceNow) < 5)
    }

    @Test func unknownDocumentIsIgnoredByTheProtocolAndThrownByTheDirectCall() async throws {
        let store = try LibraryStore.inMemory()
        let id = UUID()
        await (store as any PlayheadStore).save(SavedPlayhead(position: Position(resourceHref: "x", progression: 0),
                                                              chapterIndex: 0, secondsIntoChapter: 0), for: id)
        await #expect(throws: LibraryStoreError.documentNotFound(id)) {
            try await store.savePosition(Position(resourceHref: "x", progression: 0), for: id)
        }
    }

    /// The summary's elapsed time comes from the row and the chapters' stored durations (Plan 16):
    /// no blob is decoded, and a chapter rendered after the save still moves it.
    @Test func theSavedPlayheadGivesTheSummaryItsElapsedTime() async throws {
        let store = try LibraryStore.inMemory()
        let doc = Document(title: "D", sourceType: .epub)
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.", seconds: 2), makeUtterance("Two.", seconds: 3)],
                                                             [makeUtterance("Three.", seconds: 4, href: "ch2.xhtml")]]))
        #expect(try await store.summary(id: doc.id)?.resumeElapsedSeconds == nil)            // never played
        let p = Position(resourceHref: "ch2.xhtml", progression: 0, charOffset: 0)
        try await store.savePosition(SavedPlayhead(position: p, chapterIndex: 1, secondsIntoChapter: 1.5), for: doc.id)
        var s = try #require(try await store.summary(id: doc.id))
        #expect(s.resumeChapterIndex == 1 && s.resumeElapsedSeconds == 5 + 1.5)               // chapter 0's 5 s, then 1.5 s in
        // Chapter 0 renders longer than its estimate: the elapsed time follows without a new save.
        var chapter = try #require(try await store.chapter(0, of: doc.id))
        chapter.utterances[0].duration = .actual(6)
        try await store.saveChapter(chapter, at: 0, of: doc.id)
        s = try #require(try await store.summary(id: doc.id))
        #expect(s.resumeElapsedSeconds == 9 + 1.5)
        // A position saved on its own says nothing about time.
        try await store.savePosition(p, for: doc.id)
        #expect(try await store.summary(id: doc.id)?.resumeElapsedSeconds == nil)
    }
}
