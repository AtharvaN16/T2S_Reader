import Foundation
import Observation
import os
import T2SAudio
import T2SCore
import T2SLibrary
import T2SStore

public struct ChapterEntry: Hashable, Sendable, Identifiable {
    public var index: Int
    public var title: String
    public var startSeconds: TimeInterval
    public var durationSeconds: TimeInterval
    /// How far the playhead is through this chapter, 0…1.
    public var fraction: Double
    public var id: Int { index }

    /// One entry per chapter with its start on the (estimated) time axis and how far `elapsed` is through it.
    public static func entries(timeline: Timeline, timeIndex: TimeIndex, elapsed: TimeInterval) -> [ChapterEntry] {
        entries(axis: axis(timeline: timeline, timeIndex: timeIndex), elapsed: elapsed)
    }

    static func entries(axis: [ChapterSpan], elapsed: TimeInterval) -> [ChapterEntry] {
        axis.enumerated().map { c, span in
            ChapterEntry(index: c, title: span.title, startSeconds: span.start, durationSeconds: span.duration,
                         fraction: fraction(of: elapsed, in: span))
        }
    }

    /// Where each chapter sits on the time axis. One pass: a running utterance index, not
    /// `utteranceRange(ofChapter:)` per chapter, which made this O(chapters²) (Plan 17, audit §7).
    static func axis(timeline: Timeline, timeIndex: TimeIndex) -> [ChapterSpan] {
        var next = 0
        return timeline.chapters.map { chapter in
            let start = timeIndex.startTime(ofUtterance: next)
            next += chapter.utterances.count
            return ChapterSpan(title: chapter.title, start: start, duration: timeIndex.startTime(ofUtterance: next) - start)
        }
    }

    static func fraction(of elapsed: TimeInterval, in span: ChapterSpan) -> Double {
        span.duration > 0 ? min(1, max(0, (elapsed - span.start) / span.duration)) : 0
    }
}

/// A chapter's place on the time axis, the part of a `ChapterEntry` that only a timeline change moves.
struct ChapterSpan: Hashable, Sendable {
    var title: String
    var start: TimeInterval
    var duration: TimeInterval
}

/// The UI's one view of playback (spec §3): a thin, observable bridge over `PlaybackCoordinator`
/// plus the strings and derived shapes the player sheet and mini-player draw. It also owns the one
/// piece of persistence the coordinator does not: writing rendered chapters (actual durations, word
/// timings, audio refs) back to the store, on pause, on switching documents, and on demand.
@MainActor
@Observable
public final class PlayerModel {
    public let coordinator: PlaybackCoordinator
    /// The Preferences default voice. Applied at load to documents without a per-document override
    /// and never persisted (spec §2.2).
    public var defaultVoiceID: String?
    /// Decides, once per load, which voice the whole document actually renders with when its stored
    /// route is unavailable on this device (spec §6). The stored voice is never rewritten.
    public var voiceRouting: any VoiceRouteResolving = PassthroughVoiceRouting()
    public private(set) var current: DocumentSummary?
    /// The voice `current` actually plays with — the stored or default choice as the route resolved
    /// it on this device (spec §6), without the delivery the render carries — so it matches a
    /// catalog id. Set by every load and cleared by `unload`. The Reader's chip reads this: the
    /// summary a page was opened with is a snapshot that a voice change never touches, while a
    /// change reloads through here.
    public private(set) var routedVoiceID: String?
    /// Load or persistence failures from this model; cleared by the next successful load or persist.
    public private(set) var localError: String?
    /// The coordinator's last render error, else this model's own; the coordinator clears its error on load.
    public var renderError: String? { coordinator.lastRenderError ?? localError }

    private let library: Library
    private static let log = Logger(subsystem: "com.t2s.reader", category: "playback")
    /// Chapters to write at the next persist: the ones the coordinator reports changed, plus any
    /// whose last write failed.
    private var pendingChapters: Set<Int> = []
    /// The tick array is O(timeline) and the player sheet's body runs at 10 Hz while playing, so it
    /// is a cache invalidated by `coordinator.timelineRevision`, not a computed property.
    /// `@ObservationIgnored`: filling it from `scrubber`'s getter must not invalidate the body that
    /// is reading it.
    @ObservationIgnored private var tickCache: (revision: Int, ticks: [Bool])?
    /// The other O(timeline) facts the 10 Hz bodies read — whether every utterance is rendered, and
    /// each chapter's place on the time axis — cached against `timelineRevision` like the ticks
    /// (Plan 17, audit §7). `chapterIndexCache` is keyed on the playhead's utterance as well.
    @ObservationIgnored private var derivedCache: (revision: Int, isFullyRendered: Bool, axis: [ChapterSpan])?
    @ObservationIgnored private var chapterIndexCache: (revision: Int, utterance: Int, chapter: Int?)?
    /// The utterances of the loaded document that carry a bookmark, resolved against the
    /// coordinator's timeline, so the Reader's bookmark button can show filled while the playhead
    /// is inside one and clear it on a tap. Read from the store at load and after every change here
    /// or in `BookmarkListModel`.
    public private(set) var bookmarkedUtterances: Set<Int> = []

    public init(coordinator: PlaybackCoordinator, library: Library) {
        self.coordinator = coordinator
        self.library = library
    }

    // MARK: Derived state

    public var state: PlaybackState { coordinator.state }
    public var isPlaying: Bool { state == .playing || state == .catchingUp }
    public var isCatchingUp: Bool { state == .catchingUp }
    public var elapsed: TimeInterval { coordinator.timeIndex.time(at: coordinator.playhead) }
    public var total: TimeInterval { coordinator.timeIndex.totalDuration }
    public var isTotalApproximate: Bool { !derived().isFullyRendered }
    public var elapsedText: String { DurationFormatter.clock(elapsed) }
    public var remainingText: String { DurationFormatter.remaining(total - elapsed, approximate: isTotalApproximate) }
    public var totalText: String { (isTotalApproximate ? "~" : "") + DurationFormatter.clock(total) }
    public var chapterIndex: Int? {
        let revision = coordinator.timelineRevision
        let utterance = coordinator.playhead.utteranceIndex
        if let chapterIndexCache, chapterIndexCache.revision == revision, chapterIndexCache.utterance == utterance {
            return chapterIndexCache.chapter
        }
        let chapter = coordinator.timeline?.chapterIndex(forUtterance: utterance)
        chapterIndexCache = (revision, utterance, chapter)
        return chapter
    }

    public var chapters: [ChapterEntry] { ChapterEntry.entries(axis: derived().axis, elapsed: elapsed) }

    private func derived() -> (isFullyRendered: Bool, axis: [ChapterSpan]) {
        let revision = coordinator.timelineRevision
        if let derivedCache, derivedCache.revision == revision { return (derivedCache.isFullyRendered, derivedCache.axis) }
        guard let timeline = coordinator.timeline else { return (false, []) }
        let facts = (timeline.isFullyRendered, ChapterEntry.axis(timeline: timeline, timeIndex: coordinator.timeIndex))
        derivedCache = (revision, facts.0, facts.1)
        return facts
    }

    public var scrubber: ScrubberModel {
        let tickCount = 48
        guard let timeline = coordinator.timeline else {
            return ScrubberModel(tickCount: tickCount, renderedTicks: Array(repeating: false, count: tickCount), fraction: 0)
        }
        let revision = coordinator.timelineRevision
        let ticks: [Bool]
        if let cache = tickCache, cache.revision == revision {
            ticks = cache.ticks
        } else {
            ticks = ScrubberModel.renderedTicks(timeline: timeline, timeIndex: coordinator.timeIndex, tickCount: tickCount)
            tickCache = (revision, ticks)
        }
        let total = coordinator.timeIndex.totalDuration
        let fraction = total > 0 ? min(1, max(0, coordinator.timeIndex.time(at: coordinator.playhead) / total)) : 0
        return ScrubberModel(tickCount: tickCount, renderedTicks: ticks, fraction: fraction)
    }

    // MARK: Loading

    /// Loads a document (re-deriving a stale timeline on the way) and optionally starts playing.
    /// Whatever was loaded before is persisted first.
    public func load(_ summary: DocumentSummary, play: Bool) async {
        await load(summary, play: play, persistingCurrent: true)
    }

    /// Performs a mutation that invalidates a document's timeline or rendered audio. The currently
    /// loaded document is persisted before the mutation, then reloaded from the store afterwards.
    /// Keeping that sequence here prevents callers from accidentally writing stale audio references
    /// back after an eviction or reprocess.
    @discardableResult
    public func performDestructiveChange(
        for documentID: UUID,
        _ change: @MainActor () async throws -> Void
    ) async -> Bool {
        let reloadCurrent = current?.id == documentID
        if reloadCurrent {
            coordinator.pause()
            await persistRenderedChapters()
        }

        do {
            try await change()
            guard reloadCurrent else {
                localError = nil
                return true
            }
            guard let fresh = try await library.store.summary(id: documentID) else {
                localError = "Document is missing"
                return false
            }
            await load(fresh, play: false, persistingCurrent: false)
            return localError == nil
        } catch {
            localError = "\(error)"
            return false
        }
    }

    private func load(_ summary: DocumentSummary, play: Bool, persistingCurrent: Bool) async {
        if persistingCurrent { await persistRenderedChapters() }
        do {
            guard let timeline = try await library.timelineForPlayback(summary.id) else {
                localError = "Document is missing"
                return
            }
            var document = summary.document
            if document.voiceID == nil {
                document.voiceID = defaultVoiceID
            }
            // Local copy only: the coordinator reads this document for render keys and synthesis
            // requests, and never writes it back.
            let requestedVoiceID = document.voiceID ?? VoiceOption.systemDefault.id
            let routed = await voiceRouting.effectiveVoiceID(requestedVoiceID)
            if routed != requestedVoiceID {
                // The route, never the voice: a voice ID can carry a provider's voice name, and the
                // document's title must never reach the log.
                let route = String(requestedVoiceID.prefix { $0 != ":" })
                Self.log.notice("voice route resolved: \(route, privacy: .public) → \(routed, privacy: .public)")
            }
            // The delivery rides on the render's voice route, not on the stored choice (`Delivery`).
            document.voiceID = Delivery.applied(to: routed)
            coordinator.load(document, timeline: timeline)
            current = summary
            routedVoiceID = routed
            pendingChapters = []
            localError = nil
            await refreshBookmarks()
            if play { await coordinator.play() }
        } catch {
            localError = "\(error)"
        }
    }

    /// Drops the loaded document without persisting it — for a document the library is deleting,
    /// whose chapters and playhead row are going too. `current` is nil after, so the mini-player
    /// falls back to the queue's head and Now Playing clears.
    public func unload() {
        coordinator.unload()
        current = nil
        routedVoiceID = nil
        pendingChapters = []
        bookmarkedUtterances = []
        localError = nil
    }

    // MARK: Transport

    public func togglePlay() async {
        if isPlaying {
            coordinator.pause()
            await persistRenderedChapters()
        } else {
            await coordinator.play()
        }
    }

    public func skip(by seconds: TimeInterval) async { await coordinator.seek(toTime: elapsed + seconds) }

    public func seek(fraction: Double) async { await coordinator.seek(toTime: total * min(1, max(0, fraction))) }

    public func seek(toChapter c: Int) async {
        guard let timeline = coordinator.timeline, timeline.chapters.indices.contains(c) else { return }
        await coordinator.seek(to: Playhead(utteranceIndex: timeline.utteranceRange(ofChapter: c).lowerBound))
    }

    /// Seeks to an exact playhead, e.g. a resolved bookmark (spec §2.2).
    public func seek(to playhead: Playhead) async { await coordinator.seek(to: playhead) }

    public func setRate(_ rate: Double) { coordinator.setRate(rate) }

    public func renderWholeDocument() { coordinator.renderWholeDocument() }

    /// Whether the utterance under the playhead carries a bookmark (`bookmarkedUtterances`).
    public var isBookmarkedAtPlayhead: Bool { bookmarkedUtterances.contains(coordinator.playhead.utteranceIndex) }

    /// A bookmark at the playhead, persisted as a `Position` (spec §3.2) together with the block of
    /// text it lands on — the utterance's source, so the bookmark keeps its words even after the
    /// document is re-derived (owner's ask, 2026-09-09). False when nothing is loaded.
    public func addBookmark() async -> Bool {
        guard let current, let timeline = coordinator.timeline, timeline.utteranceCount > 0 else { return false }
        let playhead = coordinator.playhead
        let position = PositionResolver.position(for: playhead, in: timeline)
        let block = timeline[utterance: playhead.utteranceIndex].source
        do {
            try await library.store.add(Bookmark(documentID: current.id, position: position, note: block))
            bookmarkedUtterances.insert(playhead.utteranceIndex)
            return true
        } catch {
            localError = "\(error)"
            return false
        }
    }

    /// The Reader's bookmark button: removes the bookmark on the utterance under the playhead when
    /// there is one, adds one otherwise. Returns whether the utterance is bookmarked afterwards.
    public func toggleBookmark() async -> Bool {
        guard let current, let timeline = coordinator.timeline, timeline.utteranceCount > 0 else { return false }
        let utterance = coordinator.playhead.utteranceIndex
        do {
            let here = try await library.store.bookmarks(for: current.id)
                .filter { PositionResolver.resolve($0.position, in: timeline).utteranceIndex == utterance }
            guard !here.isEmpty else { return await addBookmark() }
            for bookmark in here { try await library.store.deleteBookmark(id: bookmark.id) }
            bookmarkedUtterances.remove(utterance)
            return false
        } catch {
            localError = "\(error)"
            return isBookmarkedAtPlayhead
        }
    }

    /// Re-reads the loaded document's bookmarks into `bookmarkedUtterances`. Cheap: a document
    /// has a handful, and each resolves in O(log utterances).
    public func refreshBookmarks() async {
        guard let current, let timeline = coordinator.timeline else { bookmarkedUtterances = []; return }
        let bookmarks = (try? await library.store.bookmarks(for: current.id)) ?? []
        bookmarkedUtterances = Set(bookmarks.map { PositionResolver.resolve($0.position, in: timeline).utteranceIndex })
    }

    /// Drive from a 10 Hz timer while playing (spec §3: the coordinator polls the player clock).
    public func tick() {
        coordinator.tick()
    }

    // MARK: Persistence of phase 2

    /// Writes the chapters whose utterances changed since the last write (actual durations, word
    /// timings, audio refs from `.rendered` events) — the coordinator says which (Plan 16; a pass
    /// hashing every chapter used to find them). Free when nothing changed.
    public func persistRenderedChapters() async {
        pendingChapters.formUnion(coordinator.takeChangedChapters())
        guard let current, let timeline = coordinator.timeline else { return }
        var failed = false
        pendingChapters = pendingChapters.filter { timeline.chapters.indices.contains($0) }   // a chapter of a timeline since replaced
        for c in pendingChapters.sorted() {
            let chapter = timeline.chapters[c]
            do {
                // Merge before writing: a cache-hit `.rendered` carries no word timings
                // (`RenderScheduler`), so an utterance this coordinator "rendered" straight from the
                // cache has none in memory while a prime or a Prepare pass wrote the real ones to
                // the store. Saving unmerged erased them (the Plan 13 final review, finding 2).
                let stored = try await library.store.chapter(c, of: current.id)
                let merged = stored.map { Self.merging(stored: $0, into: chapter) } ?? chapter
                try await library.store.saveChapter(merged, at: c, of: current.id)
                pendingChapters.remove(c)
            } catch {
                localError = "\(error)"
                failed = true
            }
        }
        if !failed { localError = nil }
    }

    /// Copies word timings — and an actual duration where memory only has an estimate — from the
    /// chapter the store already holds into the one about to overwrite it, for every utterance whose
    /// in-memory timings are missing and whose `audioRef` matches the stored one. The matching ref is
    /// what makes it safe: same key, same clip, so the stored timings describe the same audio.
    /// O(chapter), and it copies nothing when memory has timings of its own.
    static func merging(stored: Chapter, into chapter: Chapter) -> Chapter {
        var merged = chapter
        for i in merged.utterances.indices where i < stored.utterances.count {
            let mine = merged.utterances[i], theirs = stored.utterances[i]
            guard (mine.wordTimings ?? []).isEmpty, !(theirs.wordTimings ?? []).isEmpty,
                  let ref = mine.audioRef, ref == theirs.audioRef
            else { continue }
            merged.utterances[i].wordTimings = theirs.wordTimings
            if !mine.duration.isActual, theirs.duration.isActual { merged.utterances[i].duration = theirs.duration }
        }
        return merged
    }
}
