import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

/// A document's bookmarks, ready for a list (spec §2.2): resolved against the document's
/// timeline for the chapter, the snippet and the time. Jumping re-resolves the stored position
/// against the coordinator's own timeline, which may have been re-derived since the list was
/// built, so an utterance index never travels between two timelines.
@MainActor
@Observable
public final class BookmarkListModel {
    /// Newest first.
    public private(set) var entries: [BookmarkEntry] = []
    public private(set) var error: String?

    private let library: Library
    private let player: PlayerModel
    /// The summary this list was last loaded with, so an edit can reload without the caller
    /// passing it again.
    private var loadedSummary: DocumentSummary?
    private var currentDocumentID: UUID? { loadedSummary?.id }

    public init(library: Library, player: PlayerModel) {
        self.library = library
        self.player = player
    }

    public func load(_ summary: DocumentSummary) async {
        loadedSummary = summary
        error = nil
        do {
            let bookmarks = try await library.store.bookmarks(for: summary.id)
            guard !bookmarks.isEmpty else { entries = []; return }
            guard let timeline = try await library.currentTimeline(summary.id) else {
                // A stale document is re-derived when it is opened (`Library.timelineForPlayback`),
                // never from here (Plan 17, audit §5.1); until then its bookmarks have nothing to
                // resolve against, which is not an error. A missing document is. The Book sheet
                // loads its chapters — which re-derives — before it loads this list, so there a
                // stale book never shows an empty list; a sheet that reorders those two would.
                entries = []
                if try await library.store.document(id: summary.id) == nil { error = "Document is missing" }
                return
            }
            let index = TimeIndex(timeline)
            entries = bookmarks
                .map { bookmark in Self.displayEntry(for: bookmark, timeline: timeline, index: index) }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            self.error = "\(error)"
            entries = []
        }
    }

    public func delete(_ entry: BookmarkEntry) async {
        do {
            try await library.store.deleteBookmark(id: entry.id)
            entries.removeAll { $0.id == entry.id }
            await player.refreshBookmarks()                                 // the Reader's button, if this is the loaded book
        } catch {
            self.error = "\(error)"
        }
    }

    /// Loads the document when it is not the current one, seeks to the bookmark, and plays.
    public func jump(to entry: BookmarkEntry, in summary: DocumentSummary) async {
        if player.current?.id != summary.id { await player.load(summary, play: false) }
        guard let timeline = player.coordinator.timeline else {
            error = "Document is missing"
            return
        }
        await player.seek(to: PositionResolver.resolve(entry.position, in: timeline))
        if !player.isPlaying { await player.togglePlay() }
    }

    /// Precondition on the empty branch: a non-empty timeline never yields an out-of-range
    /// utterance index from `PositionResolver.resolve`, so the guard below only ever fires for a
    /// document with zero utterances.
    ///
    /// Public, not internal: the Reader's toast resolves the bookmark it just saved through this,
    /// and the App target cannot see T2SApp's internal symbols. `nonisolated`: it only touches its
    /// parameters, and `BookmarkGrouping` (not itself actor-isolated, so it can be tested without a
    /// player or the main actor) calls it too.
    public nonisolated static func displayEntry(for bookmark: Bookmark, timeline: Timeline, index: TimeIndex) -> BookmarkEntry {
        guard timeline.utteranceCount > 0 else {
            return BookmarkEntry(id: bookmark.id, position: bookmark.position, chapterTitle: "", passage: "",
                                 userNote: bookmark.userNote, timeSeconds: 0, endSeconds: 0, createdAt: bookmark.createdAt)
        }
        let playhead = PositionResolver.resolve(bookmark.position, in: timeline)
        let utterance = timeline[utterance: playhead.utteranceIndex]
        let chapter = timeline.chapterIndex(forUtterance: playhead.utteranceIndex).map { timeline.chapters[$0].title } ?? ""
        let raw = (bookmark.position.charOffset ?? 0) - (utterance.position.charOffset ?? 0)
        // A fallback resolution (PositionResolver.resolve, spec §1.4 "never fails") can return an
        // utterance that does not contain the bookmark's offset; show it from its start rather
        // than let a negative or out-of-range offset produce an empty passage.
        let offset = (0..<utterance.source.utf16.count).contains(raw) ? raw : 0
        // A bookmark saved with its block of text (`PlayerModel.saveBookmark`) shows that block from
        // its start; an older one, the timeline's text from the bookmark's own word.
        let passage = bookmark.passageText.map { BookmarkSnippet.make(from: $0, offset: 0) }
            ?? BookmarkSnippet.make(from: utterance.source, offset: offset)
        let start = index.time(at: playhead)
        return BookmarkEntry(id: bookmark.id,
                             position: bookmark.position,
                             chapterTitle: chapter,
                             passage: passage,
                             userNote: bookmark.userNote,
                             timeSeconds: start,
                             endSeconds: start + utterance.duration.seconds,
                             createdAt: bookmark.createdAt)
    }

    /// Writes the reader's note, or clears it when the text is blank. Reloads so the row's headline
    /// and quote follow the rule in `BookmarkEntry`, and refreshes the player's copy so the Reader's
    /// surfaces agree with this list.
    public func setNote(_ note: String?, on entry: BookmarkEntry) async {
        do {
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let all = try await library.store.bookmarks(for: currentDocumentID ?? UUID())
            guard var bookmark = all.first(where: { $0.id == entry.id }) else { return }
            bookmark.userNote = (trimmed?.isEmpty ?? true) ? nil : trimmed
            try await library.store.add(bookmark)
            await player.refreshBookmarks()
            if let summary = loadedSummary { await load(summary) }
        } catch {
            self.error = "\(error)"
        }
    }
}
