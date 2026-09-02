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
