import Foundation
import Testing
import T2SAudio
import T2SCore
import T2SStore
@testable import T2SApp

@MainActor
@Suite struct BookmarkListModelTests {
    /// The same player the PlayerModel tests build; the engine is held so the time axis stays
    /// the estimated one the assertions were written against.
    func makePlayer(_ f: AppFixtures) async throws -> (PlayerModel, FakeEngine) {
        let engine = FakeEngine(secondsPerCharacter: 0.05)
        await engine.hold()
        let coordinator = PlaybackCoordinator(engine: engine, store: f.audio,
                                              player: try AudioPlayer(manualRendering: true), playheadStore: f.store,
                                              timeSource: SystemTimeSource())
        return (PlayerModel(coordinator: coordinator, library: f.library), engine)
    }

    @Test func listsBookmarksNewestFirstWithChapterSnippetAndTime() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        #expect(await player.addBookmark())                 // chapter 1, "First sentence."
        await player.seek(toChapter: 1)
        #expect(await player.addBookmark())                 // chapter 2, "Sentence number 2 here."

        let model = BookmarkListModel(library: f.library, player: player)
        await model.load(summary)
        #expect(model.error == nil)
        #expect(model.entries.count == 2)
        #expect(model.entries[0].chapterTitle == "Chapter 2")
        #expect(model.entries[0].snippet == "Sentence number 2 here.")
        #expect(model.entries[0].timeSeconds == player.chapters[1].startSeconds)
        #expect(model.entries[1].chapterTitle == "Chapter 1")
        #expect(model.entries[1].snippet == "First sentence.")
        #expect(model.entries[1].timeText == "0:00")
        #expect(model.entries[0].createdAt >= model.entries[1].createdAt)
    }

    @Test func deleteRemovesTheBookmarkFromTheStoreAndTheList() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        #expect(await player.addBookmark())
        let model = BookmarkListModel(library: f.library, player: player)
        await model.load(summary)
        let entry = try #require(model.entries.first)
        await model.delete(entry)
        #expect(model.entries.isEmpty)
        #expect(try await f.store.bookmarks(for: id).isEmpty)
    }

    @Test func jumpLoadsSeeksAndPlays() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        await player.seek(toChapter: 1)
        #expect(await player.addBookmark())
        let model = BookmarkListModel(library: f.library, player: player)
        await model.load(summary)
        let entry = try #require(model.entries.first)

        // A fresh player: the jump must load the document itself.
        let (other, _) = try await makePlayer(f)
        let otherModel = BookmarkListModel(library: f.library, player: other)
        await otherModel.jump(to: entry, in: summary)
        #expect(other.current?.id == id)
        #expect(other.chapterIndex == 1)
        #expect(other.isPlaying)
    }

    @Test func aDocumentWithoutBookmarksListsNothing() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        let model = BookmarkListModel(library: f.library, player: player)
        await model.load(summary)
        #expect(model.entries.isEmpty && model.error == nil)
    }
}
