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
        // `sort` defaults to what was last chosen on this device, so a test that cares about the
        // order says which one it means rather than inheriting a stored preference.
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        #expect(await player.saveBookmark() != .failed)     // chapter 1, "First sentence."
        await player.seek(toChapter: 1)
        #expect(await player.saveBookmark() != .failed)     // chapter 2, "Sentence number 2 here."

        let model = BookmarkListModel(library: f.library, player: player)
        model.sort = .recent
        await model.load(summary)
        #expect(model.error == nil)
        #expect(model.entries.count == 2)
        #expect(model.entries[0].chapterTitle == "Chapter 2")
        #expect(model.entries[0].passage == "Sentence number 2 here.")
        #expect(model.entries[0].timeSeconds == player.chapters[1].startSeconds)
        #expect(model.entries[1].chapterTitle == "Chapter 1")
        #expect(model.entries[1].passage == "First sentence.")
        #expect(model.entries[1].timeText == "0:00")
        #expect(model.entries[0].createdAt >= model.entries[1].createdAt)
    }

    /// A bookmark saved with its block of text shows that block whole, from its start, even when
    /// its position points into the middle of the sentence; one saved without it (older builds)
    /// shows the timeline's text from the bookmark's word.
    @Test func snippetPrefersTheSavedBlockOfText() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        let timeline = try #require(player.coordinator.timeline)
        let first = timeline[utterance: 0]
        let midWord = Position(resourceHref: first.position.resourceHref, progression: first.position.progression,
                               charOffset: (first.position.charOffset ?? 0) + 6)
        try await f.store.add(Bookmark(documentID: id, position: midWord, passageText: first.source, createdAt: Date(timeIntervalSince1970: 2)))
        try await f.store.add(Bookmark(documentID: id, position: midWord, passageText: nil, createdAt: Date(timeIntervalSince1970: 1)))

        let model = BookmarkListModel(library: f.library, player: player)
        // Both sit at one position, so book order ties them and breaks it on `createdAt` the other
        // way about; this test is about which text a row shows, not which row comes first.
        model.sort = .recent
        await model.load(summary)
        #expect(model.entries.count == 2)
        #expect(model.entries[0].passage == "First sentence.")               // the saved block
        #expect(model.entries[1].passage == "sentence.")                     // from the word, as before
    }

    /// Deleting from the list keeps the player's own `bookmarks` list honest for the loaded book.
    @Test func deleteRefreshesThePlayersBookmarks() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        #expect(await player.saveBookmark() != .failed)
        #expect(player.bookmarks.count == 1)
        let model = BookmarkListModel(library: f.library, player: player)
        await model.load(summary)
        await model.delete(try #require(model.entries.first))
        #expect(player.bookmarks.isEmpty)
    }

    /// A stale document is re-derived when it is opened, never by the bookmark list (Plan 17, audit
    /// §5.1): until then the list is empty, and that is not an error.
    @Test func aStaleDocumentListsNoBookmarksAndNoError() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        try await f.store.add(Bookmark(documentID: id, position: Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0, charOffset: 0)))
        var stale = try #require(try await f.store.timeline(for: id)).timeline
        stale.segmenterVersion = Versions.segmenter + 1
        try await f.store.replaceTimeline(stale, for: id)
        let (player, _) = try await makePlayer(f)
        let model = BookmarkListModel(library: f.library, player: player)
        await model.load(summary)
        #expect(model.entries.isEmpty && model.error == nil)
        #expect(try await f.store.isStale(id: id) == true)                  // not re-derived from here
    }

    @Test func deleteRemovesTheBookmarkFromTheStoreAndTheList() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        #expect(await player.saveBookmark() != .failed)
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
        #expect(await player.saveBookmark() != .failed)
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

    /// A stale or lost href sends `PositionResolver.resolve` to its final fallback — utterance 0
    /// (spec §1.4 "never fails") — whose source ends well before `charOffset` 4000. The snippet
    /// must show that utterance from its start rather than come back empty.
    @Test func aBookmarkThatResolvesPastItsUtteranceStillShowsANonEmptySnippet() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        try await f.store.add(Bookmark(documentID: id,
            position: Position(resourceHref: "OEBPS/missing.xhtml", progression: 0, charOffset: 4000)))

        let model = BookmarkListModel(library: f.library, player: player)
        await model.load(summary)
        #expect(model.error == nil)
        #expect(model.entries.count == 1)
        let entry = try #require(model.entries.first)
        #expect(entry.chapterTitle == "Chapter 1")
        #expect(!entry.passage.isEmpty)
        #expect(entry.passage == BookmarkSnippet.make(from: "First sentence.", offset: 0))
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

    @Test func theReadersNoteBecomesTheHeadlineAndThePassageBecomesTheQuote() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        #expect(await player.saveBookmark() != .failed)

        let model = BookmarkListModel(library: f.library, player: player)
        await model.load(summary)
        let before = try #require(model.entries.first)
        #expect(before.headline == "First sentence.")
        #expect(before.quote == nil)
        #expect(before.endSeconds > before.timeSeconds)
        #expect(before.rangeText == "\(DurationFormatter.clock(before.timeSeconds)) – \(DurationFormatter.clock(before.endSeconds))")

        await model.setNote("my own words", on: before)
        let after = try #require(model.entries.first)
        #expect(after.headline == "my own words")
        #expect(after.quote == "First sentence.")

        await model.setNote("   ", on: after)
        #expect(model.entries.first?.headline == "First sentence.")
        #expect(model.entries.first?.quote == nil)
    }

    /// Book order is the order the book goes in, not the order the bookmarks were written — which
    /// for anyone listening straight through is the same list backwards (owner, 2026-09-12). Saved
    /// saved in the order a listener would save them — chapter 1, then chapter 2 — which is the
    /// arrangement where the two orders disagree and one list is the other backwards.
    @Test func ordersByPlaceInTheBookAndByWhenSavedOnAsk() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        #expect(await player.saveBookmark() != .failed)                  // chapter 1, saved first
        await player.seek(toChapter: 1)
        #expect(await player.saveBookmark() != .failed)                  // chapter 2, saved second

        let model = BookmarkListModel(library: f.library, player: player)
        model.sort = .book
        await model.load(summary)
        #expect(model.entries.map(\.chapterTitle) == ["Chapter 1", "Chapter 2"])
        #expect(model.entries[0].timeSeconds < model.entries[1].timeSeconds)

        // Reordering is done on what is already loaded — no reload — so the control answers at once.
        model.sort = .recent
        #expect(model.entries.map(\.chapterTitle) == ["Chapter 2", "Chapter 1"])
        #expect(model.entries[0].createdAt >= model.entries[1].createdAt)

        // And the choice outlives the model that made it.
        #expect(BookmarkSort.remembered == .recent)
        model.sort = .book
        #expect(BookmarkSort.remembered == .book)
    }

    /// A note has no length limit anywhere — not in the store, not on `BookmarkEntry` — so a long
    /// one has to survive whole; only a row clips it, and only for as long as it is a row
    /// (`BookmarkDetail` prints the rest). The book's passage is the opposite case: `BookmarkSnippet`
    /// caps it at 90 UTF-16 units for the row, while `fullPassage` keeps what was saved. Asked for
    /// after the owner asked whether long ones had been tested (2026-09-12): they had not.
    @Test func aLongNoteAndALongPassageBothSurviveWhole() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        let timeline = try #require(player.coordinator.timeline)
        let first = timeline[utterance: 0]
        let longPassage = String(repeating: "the passage runs on and on ", count: 60)   // ~1,600 units
        try await f.store.add(Bookmark(documentID: id, position: first.position,
                                       passageText: longPassage, createdAt: Date(timeIntervalSince1970: 1)))

        let model = BookmarkListModel(library: f.library, player: player)
        await model.load(summary)
        var entry = try #require(model.entries.first)
        // Trimmed for the row, kept for the screen that has room.
        #expect(entry.passage.utf16.count <= BookmarkSnippet.maxLength)
        #expect(entry.passage.hasSuffix("…"))
        #expect(entry.fullPassage == longPassage)
        #expect(entry.headline == entry.passage)                         // no note yet: the book's words lead

        let typed = String(repeating: "and then I thought about it some more ", count: 80)      // ~3,000
        let stored = typed.trimmingCharacters(in: .whitespacesAndNewlines)                      // `setNote` trims
        await model.setNote(typed, on: entry)
        entry = try #require(model.entries.first)
        #expect(stored.utf16.count > 2_000)
        #expect(entry.hasNote)
        #expect(entry.userNote == stored)                                // the trailing space, and nothing else
        #expect(entry.headline == stored)                                // the reader's words lead, in full
        #expect(entry.quote == entry.passage)                            // and the book's drop to the quote
        #expect(model.error == nil)
    }
}
