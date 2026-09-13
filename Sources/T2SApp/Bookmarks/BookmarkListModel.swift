import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

/// The order a document's bookmarks are listed in (owner, 2026-09-12). Book order leads, and the
/// reason is that `createdAt` descending — the only order there used to be — is book order backwards
/// for anyone listening straight through: the place you reached last stands at the top and the
/// opening of the book at the foot. A bookmark is a place in a story, and a story has an order.
/// "Recently added" is still worth having for the one question the other cannot answer, which is
/// what you just saved. Remembered across launches: a reader who has stated a preference should not
/// restate it.
public enum BookmarkSort: String, CaseIterable, Sendable {
    case book, recent

    public var title: String {
        switch self {
        case .book: return "Reading order"
        case .recent: return "Recently added"
        }
    }

    private static let key = "bookmarks.sort"

    public static var remembered: BookmarkSort {
        UserDefaults.standard.string(forKey: key).flatMap(BookmarkSort.init(rawValue:)) ?? .book
    }

    public static func remember(_ sort: BookmarkSort) {
        UserDefaults.standard.set(sort.rawValue, forKey: key)
    }
}

/// A document's bookmarks, ready for a list (spec §2.2): resolved against the document's
/// timeline for the chapter, the snippet and the time. Jumping re-resolves the stored position
/// against the coordinator's own timeline, which may have been re-derived since the list was
/// built, so an utterance index never travels between two timelines.
@MainActor
@Observable
public final class BookmarkListModel {
    /// In ``sort``'s order.
    public private(set) var entries: [BookmarkEntry] = []
    public private(set) var error: String?
    /// The order the list is in. Setting it reorders what is already loaded — no round trip to the
    /// store, which is what lets the control feel like a control — and remembers the choice.
    public var sort: BookmarkSort = .remembered {
        didSet {
            guard sort != oldValue else { return }
            BookmarkSort.remember(sort)
            entries = Self.ordered(entries, by: sort)
        }
    }

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
            entries = Self.ordered(bookmarks.map { bookmark in
                Self.displayEntry(for: bookmark, timeline: timeline, index: index)
            }, by: sort)
        } catch {
            self.error = "\(error)"
            entries = []
        }
    }

    /// Book order is the time the bookmark sits at, and `createdAt` breaks a tie: two bookmarks in
    /// one utterance share a second, and without the tie-break they would trade places on reload.
    nonisolated static func ordered(_ entries: [BookmarkEntry], by sort: BookmarkSort) -> [BookmarkEntry] {
        switch sort {
        case .book:
            return entries.sorted {
                $0.timeSeconds == $1.timeSeconds ? $0.createdAt < $1.createdAt : $0.timeSeconds < $1.timeSeconds
            }
        case .recent:
            return entries.sorted { $0.createdAt > $1.createdAt }
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
        // `offset` counts UTF-16 units, as every offset in `Position` does.
        let source = bookmark.passageText
            ?? String(utterance.source[String.Index(utf16Offset: offset, in: utterance.source)...])
        let passage = bookmark.passageText.map { BookmarkSnippet.make(from: $0, offset: 0) }
            ?? BookmarkSnippet.make(from: utterance.source, offset: offset)
        let start = index.time(at: playhead)
        return BookmarkEntry(id: bookmark.id,
                             position: bookmark.position,
                             chapterTitle: chapter,
                             passage: passage,
                             fullPassage: source,
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
