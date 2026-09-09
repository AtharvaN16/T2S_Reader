import Foundation
import Testing
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct LibraryModelTests {
    @Test func refreshBuildsQueueAndProgress() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake(), b = try await f.importFake()
        let model = LibraryModel(library: f.library)
        await model.refresh()
        #expect(model.queue.map(\.id) == [a, b])
        #expect(model.finished.isEmpty)
        let collectionIDs: [UUID] = model.collection.map(\.id).sorted(by: { $0.uuidString < $1.uuidString })
        let expectedIDs: [UUID] = [a, b].sorted(by: { $0.uuidString < $1.uuidString })
        #expect(collectionIDs == expectedIDs)
        #expect(!model.isQueueEmpty)
        let progress = try #require(model.progress(for: a))
        #expect(progress.chapterCount == 2 && progress.elapsedSeconds == 0 && progress.isApproximate)
        #expect(model.queueSubtitle.hasPrefix("2 items · ~"))
    }

    @Test func archiveEnqueueMoveFinishDelete() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake(), b = try await f.importFake(), c = try await f.importFake()
        let model = LibraryModel(library: f.library)
        await model.refresh()
        await model.archive(a)
        #expect(model.queue.map(\.id) == [b, c])
        await model.enqueue(a)
        #expect(model.queue.map(\.id) == [b, c, a])
        await model.move(a, to: 0)
        #expect(model.queue.map(\.id) == [a, b, c])
        await model.markFinished(b, true)
        #expect(model.queue.map(\.id) == [a, c])
        #expect(model.finished.map(\.id) == [b])
        model.queueView = .finished
        #expect(model.visibleRows.map(\.id) == [b])
        await model.markFinished(b, false)                                  // back to the end of the Queue
        #expect(model.queue.map(\.id) == [a, c, b])
        await model.delete(c)
        #expect(model.queue.map(\.id) == [a, b])
        #expect(try await f.store.document(id: c) == nil)
        #expect(model.lastError == nil)
    }

    @Test func emptyLibraryIsEmptyQueue() async throws {
        let f = try AppFixtures()
        let model = LibraryModel(library: f.library)
        await model.refresh()
        #expect(model.isQueueEmpty && model.queueSubtitle == "0 items")
    }

    @Test func refreshReusesProgressForUnchangedDocuments() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake()
        _ = try await f.importFake()
        let model = LibraryModel(library: f.library)
        await model.refresh()
        let first = model.progress
        #expect(first.count == 2)
        await model.refresh()                                               // nothing written: every row is a cache hit
        #expect(model.progress == first)
        try await f.store.savePosition(Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0), for: a)
        await model.refresh()                                               // …but a new resume position is not
        #expect(model.progress != first)
        #expect(model.progress(for: a)?.chapterIndex == 1)
    }

    /// A row the coordinator has played carries its own elapsed time (Plan 16): progress comes from
    /// the summary and the chapter blobs stay on disk.
    @Test func progressComesFromTheSavedPlayhead() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake()
        let model = LibraryModel(library: f.library)
        let playhead: any PlayheadStore = f.store
        await playhead.save(SavedPlayhead(position: Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0),
                                          chapterIndex: 1, secondsIntoChapter: 0.25), for: a)
        await model.refresh()
        let p = try #require(model.progress(for: a))
        let s = try #require(model.summaries.first { $0.id == a })
        let elapsed = try #require(s.resumeElapsedSeconds)
        #expect(p.chapterIndex == 1 && p.chapterCount == 2)
        #expect(abs(p.elapsedSeconds - elapsed) < 1e-9 && elapsed > 0.25)                     // chapter 1's duration, then 0.25 s
        #expect(p.totalSeconds == s.totalSeconds && p.isApproximate)
    }

    /// A chapter of known sentences with a resume position on the second: the Home row's excerpt
    /// starts there, runs on, and is one line however the source was broken.
    @Test func excerptStartsAtTheResumePosition() async throws {
        let f = try AppFixtures()
        func chapter(_ sentences: [String]) -> Chapter {
            var offset = 0
            var utterances: [Utterance] = []
            for text in sentences {
                let n = text.utf16.count
                utterances.append(Utterance(position: Position(resourceHref: "a", progression: 0, charOffset: offset),
                                            source: text, spoken: text, spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)],
                                            duration: .estimated(2)))
                offset += n + 1
            }
            return Chapter(title: "One", position: Position(resourceHref: "a", progression: 0, charOffset: 0), utterances: utterances)
        }
        let one = chapter(["Alpha starts the chapter.", "Beta is where\nwe   stopped.", "Gamma follows.", "Delta ends it."])
        let second = try #require(one.utterances[1].position.charOffset)
        let document = Document(title: "Excerpt", sourceType: .epub,
                                resumePosition: Position(resourceHref: "a", progression: 0, charOffset: second))
        try await f.store.insert(document, timeline: Timeline(chapters: [one]), queued: true)
        let model = LibraryModel(library: f.library)
        await model.refresh()
        let s = try #require(model.summaries.first { $0.id == document.id })
        let excerpt = try #require(await model.excerpt(for: s))
        #expect(excerpt.hasPrefix("Beta is where we stopped."))                      // whitespace runs collapse
        #expect(excerpt.contains("Gamma follows."))
        #expect(!excerpt.contains("Alpha"))
        #expect(excerpt == "Beta is where we stopped. Gamma follows. Delta ends it.")
        // The same decode says where in the chapter that is: one 2 s utterance in, four in all.
        let glimpse = try #require(await model.glimpse(for: s))
        #expect(glimpse.chapterElapsedSeconds == 2)
        #expect(glimpse.chapterTotalSeconds == 8)
        #expect(glimpse.chapterFraction == 0.25)
        #expect(glimpse.chapterRemainingSeconds == 6)

        // A moved position is a new key: the excerpt follows it.
        let third = try #require(one.utterances[2].position.charOffset)
        try await f.store.savePosition(Position(resourceHref: "a", progression: 0, charOffset: third), for: document.id)
        await model.refresh()
        let moved = try #require(model.summaries.first { $0.id == document.id })
        #expect(await model.excerpt(for: moved) == "Gamma follows. Delta ends it.")
        #expect(await model.glimpse(for: moved)?.chapterElapsedSeconds == 4)

        // No resume position reads from the top; enough text stops the join short of the chapter's end.
        let long = String(repeating: "Long sentence here. ", count: 12).trimmingCharacters(in: .whitespaces)   // 239 chars
        let fresh = Document(title: "Fresh", sourceType: .epub)
        try await f.store.insert(fresh, timeline: Timeline(chapters: [chapter(["Top.", long, "Omega is past the cut."])]), queued: true)
        await model.refresh()
        let top = try #require(model.summaries.first { $0.id == fresh.id })
        let fromTop = try #require(await model.excerpt(for: top))
        #expect(fromTop.hasPrefix("Top. Long sentence here."))
        #expect(!fromTop.contains("Omega"))

        // A document the store no longer has is nil, not an error.
        var gone = s
        gone.document.id = UUID()
        #expect(await model.excerpt(for: gone) == nil)
    }

    @Test func progressFollowsSavedPositions() async throws {
        let f = try AppFixtures()
        let a = try await f.importFake()
        let model = LibraryModel(library: f.library)
        try await f.store.savePosition(Position(resourceHref: "OEBPS/ch2.xhtml", progression: 0, charOffset: 0), for: a)
        await model.refresh()
        let p = try #require(model.progress(for: a))
        #expect(p.chapterIndex == 1)
        #expect(p.elapsedSeconds > 0 && p.remainingSeconds < p.totalSeconds)
    }
}
