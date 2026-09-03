import Foundation
import SwiftData
import Testing
import T2SCore
@testable import T2SStore

@Suite struct LibraryStoreTests {
    /// Exactly representable as a Double, so it survives the SQLite round trip unchanged.
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    func makeDocument(_ title: String = "Doc", type: SourceType = .epub) -> Document {
        Document(title: title, author: "A. Author", sourceType: type,
                 sourceURL: URL(string: "https://example.com/a"), addedAt: fixedDate)
    }

    @Test func insertAndFetchRoundTrip() async throws {
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        let timeline = makeTimeline([[makeUtterance("One."), makeUtterance("Two.", charOffset: 5)],
                                     [makeUtterance("Three.", href: "ch2.xhtml")]])
        try await store.insert(doc, timeline: timeline)
        #expect(try await store.document(id: doc.id) == doc)
        #expect(try await store.timeline(for: doc.id) == StoredTimeline(timeline: timeline, isStale: false))
        #expect(try await store.chapter(1, of: doc.id) == timeline.chapters[1])
        #expect(try await store.chapter(2, of: doc.id) == nil)
        #expect(try await store.timeline(for: UUID()) == nil)
    }

    @Test func duplicateInsertThrows() async throws {
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        await #expect(throws: LibraryStoreError.duplicateDocument(doc.id)) {
            try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        }
    }

    @Test func staleWhenVersionsDiffer() async throws {
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        var timeline = makeTimeline([[makeUtterance("One.")]])
        timeline.segmenterVersion = Versions.segmenter + 1
        try await store.insert(doc, timeline: timeline)
        let stored = try #require(try await store.timeline(for: doc.id))
        #expect(stored.isStale)
        #expect(stored.timeline.segmenterVersion == Versions.segmenter + 1)

        let normalizerStale = makeDocument("normalizer-stale")
        var normalizerTimeline = makeTimeline([[makeUtterance("One.")]])
        normalizerTimeline.normalizerVersion = Versions.normalizer + 1
        try await store.insert(normalizerStale, timeline: normalizerTimeline)
        let normalizerStored = try #require(try await store.timeline(for: normalizerStale.id))
        #expect(normalizerStored.isStale)

        let current = makeDocument("current")
        try await store.insert(current, timeline: makeTimeline([[makeUtterance("One.")]]))
        let currentStored = try #require(try await store.timeline(for: current.id))
        #expect(!currentStored.isStale)
    }

    @Test func deleteCascadesChapters() async throws {
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")],
                                                            [makeUtterance("Two.", href: "ch2.xhtml")]]))
        #expect(try await store.chapterRowCount() == 2)
        try await store.delete(id: doc.id)
        #expect(try await store.document(id: doc.id) == nil)
        #expect(try await store.chapterRowCount() == 0)
        await #expect(throws: LibraryStoreError.documentNotFound(doc.id)) { try await store.delete(id: doc.id) }
    }

    @Test func queueOrderingAndMoves() async throws {
        let store = try LibraryStore.inMemory()
        let a = makeDocument("a"), b = makeDocument("b"), c = makeDocument("c")
        for d in [a, b, c] {
            try await store.insert(d, timeline: makeTimeline([[makeUtterance("x")]]))
            try await store.setQueued(d.id, true)
        }
        #expect(try await store.queue().map(\.id) == [a.id, b.id, c.id])
        try await store.setQueued(a.id, true)                              // idempotent
        #expect(try await store.queue().map(\.id) == [a.id, b.id, c.id])
        try await store.moveInQueue(c.id, to: 0)
        #expect(try await store.queue().map(\.id) == [c.id, a.id, b.id])
        try await store.setQueued(a.id, false)                             // archive
        #expect(try await store.queue().map(\.id) == [c.id, b.id])
        #expect(try await store.summary(id: c.id)?.queueOrder == 0)
        #expect(try await store.summary(id: b.id)?.queueOrder == 1)
        try await store.setQueued(a.id, true)                              // back at the end
        #expect(try await store.queue().map(\.id) == [c.id, b.id, a.id])
        #expect(try await store.summary(id: a.id)?.queueOrder == 2)
        try await store.moveInQueue(c.id, to: 99)                          // clamped
        #expect(try await store.queue().map(\.id) == [b.id, a.id, c.id])
        #expect(try await store.summary(id: b.id)?.queueOrder == 0)
    }

    @Test func finishLeavesTheQueueAndUnfinishReturnsToTheEnd() async throws {
        let store = try LibraryStore.inMemory()
        let a = makeDocument("a"), b = makeDocument("b"), c = makeDocument("c")
        for d in [a, b, c] {
            try await store.insert(d, timeline: makeTimeline([[makeUtterance("x")]]))
            try await store.setQueued(d.id, true)
        }
        try await store.finish(a.id, true)
        #expect(try await store.queue().map(\.id) == [b.id, c.id])
        #expect(try await store.summary(id: a.id)?.isFinished == true)
        #expect(try await store.summary(id: b.id)?.queueOrder == 0)
        #expect(try await store.summary(id: c.id)?.queueOrder == 1)
        try await store.finish(a.id, false)
        #expect(try await store.queue().map(\.id) == [b.id, c.id, a.id])
        #expect(try await store.summary(id: a.id)?.isFinished == false)
        #expect(try await store.summary(id: a.id)?.queueOrder == 2)
        try await store.finish(a.id, false)                                   // idempotent
        #expect(try await store.queue().map(\.id) == [b.id, c.id, a.id])
    }

    @Test func insertQueuedJoinsTheEndOfTheQueueAtomically() async throws {
        let store = try LibraryStore.inMemory()
        let a = makeDocument("a"), b = makeDocument("b")
        try await store.insert(a, timeline: makeTimeline([[makeUtterance("x")]]), queued: true)
        try await store.insert(b, timeline: makeTimeline([[makeUtterance("x")]]), queued: true)
        #expect(try await store.queue().map(\.id) == [a.id, b.id])
        #expect(try await store.summary(id: b.id)?.queueOrder == 1)
        let c = makeDocument("c")
        try await store.insert(c, timeline: makeTimeline([[makeUtterance("x")]]))
        #expect(try await store.summary(id: c.id)?.queueOrder == nil)
    }

    @Test func collectionHoldsBooksOnly() async throws {
        let store = try LibraryStore.inMemory()
        let epub = makeDocument("e", type: .epub), pdf = makeDocument("p", type: .pdf)
        let article = makeDocument("w", type: .article)
        for d in [epub, pdf, article] { try await store.insert(d, timeline: makeTimeline([[makeUtterance("x")]])) }
        #expect(Set(try await store.collection().map(\.id)) == [epub.id, pdf.id])
        #expect(try await store.documents().count == 3)
    }

    @Test func saveChapterRefreshesSummary() async throws {
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        var timeline = makeTimeline([[makeUtterance("One.", seconds: 1), makeUtterance("Two.", seconds: 1)]])
        try await store.insert(doc, timeline: timeline)
        var s = try #require(try await store.summary(id: doc.id))
        #expect(s.utteranceCount == 2 && s.renderedCount == 0 && s.chapterCount == 1)
        #expect(s.totalSeconds == 2)
        #expect(!s.isFullyRendered)

        timeline[utterance: 0].duration = .actual(1.5)
        timeline[utterance: 0].audioRef = "abc"
        timeline[utterance: 0].wordTimings = [WordTiming(spokenRange: 0..<4, start: 0, end: 1.5)]
        try await store.saveChapter(timeline.chapters[0], at: 0, of: doc.id)
        s = try #require(try await store.summary(id: doc.id))
        #expect(s.renderedCount == 1 && s.totalSeconds == 2.5)
        #expect(try await store.chapter(0, of: doc.id) == timeline.chapters[0])
        await #expect(throws: LibraryStoreError.chapterOutOfRange(5)) {
            try await store.saveChapter(timeline.chapters[0], at: 5, of: doc.id)
        }
    }

    @Test func replaceTimelineKeepsResumePosition() async throws {
        let store = try LibraryStore.inMemory()
        var doc = makeDocument()
        doc.resumePosition = Position(resourceHref: "ch1.xhtml", progression: 0, charOffset: 3)
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        let fresh = makeTimeline([[makeUtterance("One."), makeUtterance("Two.", charOffset: 5)]])
        try await store.replaceTimeline(fresh, for: doc.id)
        #expect(try await store.timeline(for: doc.id) == StoredTimeline(timeline: fresh, isStale: false))
        #expect(try await store.document(id: doc.id)?.resumePosition == doc.resumePosition)
        #expect(try await store.chapterRowCount() == 1)
    }

    @Test func updateChangesMetadataOnly() async throws {
        let store = try LibraryStore.inMemory()
        var doc = makeDocument()
        doc.resumePosition = Position(resourceHref: "ch1.xhtml", progression: 0.5)
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        var edited = doc
        edited.title = "Renamed"
        edited.voiceID = "af_heart"
        edited.coverImagePath = "Documents/x/cover.jpg"
        edited.resumePosition = nil                                        // ignored by update
        try await store.update(edited)
        let got = try #require(try await store.document(id: doc.id))
        #expect(got.title == "Renamed" && got.voiceID == "af_heart" && got.coverImagePath == "Documents/x/cover.jpg")
        #expect(got.resumePosition == doc.resumePosition)
    }

    @Test func onDiskStoreReopens() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-store-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("Library.store")
        let doc = makeDocument()
        do {
            let store = try LibraryStore.onDisk(at: url)
            try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        }
        let reopened = try LibraryStore.onDisk(at: url)
        #expect(try await reopened.document(id: doc.id) == doc)
        #expect(try await reopened.timeline(for: doc.id)?.timeline.utteranceCount == 1)
    }

    @Test func schemaIsVersioned() async throws {
        #expect(LibrarySchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        #expect(try await store.document(id: doc.id) == doc)
    }

    @Test func summariesNewestFirst() async throws {
        let store = try LibraryStore.inMemory()
        let old = Document(title: "old", sourceType: .epub, addedAt: fixedDate)
        let new = Document(title: "new", sourceType: .epub, addedAt: fixedDate.addingTimeInterval(60))
        try await store.insert(old, timeline: makeTimeline([[makeUtterance("x")]]))
        try await store.insert(new, timeline: makeTimeline([[makeUtterance("x")]]))
        #expect(try await store.summaries().map(\.document.title) == ["new", "old"])
        try await store.setFinished(old.id, true)
        #expect(try await store.summary(id: old.id)?.isFinished == true)
    }
}
