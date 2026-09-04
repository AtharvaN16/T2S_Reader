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

    public init(library: Library, player: PlayerModel) {
        self.library = library
        self.player = player
    }

    public func load(_ summary: DocumentSummary) async {
        error = nil
        do {
            let bookmarks = try await library.store.bookmarks(for: summary.id)
            guard !bookmarks.isEmpty else { entries = []; return }
            guard let timeline = try await library.timelineForPlayback(summary.id) else {
                entries = []
                error = "Document is missing"
                return
            }
            let index = TimeIndex(timeline)
            entries = bookmarks
                .map { bookmark in Self.entry(for: bookmark, timeline: timeline, index: index) }
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
    private static func entry(for bookmark: Bookmark, timeline: Timeline, index: TimeIndex) -> BookmarkEntry {
        guard timeline.utteranceCount > 0 else {
            return BookmarkEntry(id: bookmark.id, position: bookmark.position, chapterTitle: "",
                                 snippet: "", timeSeconds: 0, createdAt: bookmark.createdAt)
        }
        let playhead = PositionResolver.resolve(bookmark.position, in: timeline)
        let utterance = timeline[utterance: playhead.utteranceIndex]
        let chapter = timeline.chapterIndex(forUtterance: playhead.utteranceIndex).map { timeline.chapters[$0].title } ?? ""
        let raw = (bookmark.position.charOffset ?? 0) - (utterance.position.charOffset ?? 0)
        // A fallback resolution (PositionResolver.resolve, spec §1.4 "never fails") can return an
        // utterance that does not contain the bookmark's offset; show it from its start rather
        // than let a negative or out-of-range offset produce an empty snippet.
        let offset = (0..<utterance.source.utf16.count).contains(raw) ? raw : 0
        return BookmarkEntry(id: bookmark.id,
                             position: bookmark.position,
                             chapterTitle: chapter,
                             snippet: BookmarkSnippet.make(from: utterance.source, offset: offset),
                             timeSeconds: index.time(at: playhead),
                             createdAt: bookmark.createdAt)
    }
}
