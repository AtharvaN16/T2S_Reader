import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

public enum QueueView: Hashable, Sendable { case queue, finished }

/// What the Home row shows of one document's place in it, read from the resume chapter alone
/// (`LibraryModel.glimpse(for:)`).
public struct RowGlimpse: Hashable, Sendable {
    /// A few lines of text from the resume position on; nil when the chapter has no text.
    public var excerpt: String?
    /// Seconds into the resume chapter at 1x, and the chapter's whole length.
    public var chapterElapsedSeconds: TimeInterval
    public var chapterTotalSeconds: TimeInterval

    public var chapterFraction: Double {
        chapterTotalSeconds > 0 ? min(1, max(0, chapterElapsedSeconds / chapterTotalSeconds)) : 0
    }
    public var chapterRemainingSeconds: TimeInterval { max(0, chapterTotalSeconds - chapterElapsedSeconds) }

    public init(excerpt: String?, chapterElapsedSeconds: TimeInterval, chapterTotalSeconds: TimeInterval) {
        self.excerpt = excerpt
        self.chapterElapsedSeconds = chapterElapsedSeconds
        self.chapterTotalSeconds = chapterTotalSeconds
    }
}

/// The Queue and Collection pages' state (spec §2.3, §2.4.5). Reads summaries from the store and
/// per-document progress from the summary itself where the coordinator has saved a playhead
/// (Plan 16), else through `Library.currentTimeline`, which decodes the stored chapters but
/// never reprocesses: re-derivation after a version bump is a load-time concern
/// (`Library.timelineForPlayback`), not something an action's refresh should trigger for every
/// queued document at once. Progress is cached per document against the parts of its summary that
/// can change it, so a refresh after an archive or a move decodes only what actually changed. A
/// document with no progress entry (stale, or missing) falls back to the summary's own totals.
@MainActor
@Observable
public final class LibraryModel {
    public private(set) var summaries: [DocumentSummary] = []
    public private(set) var progress: [UUID: DocumentProgress] = [:]
    public var queueView: QueueView = .queue
    public private(set) var lastError: String?

    private let library: Library
    /// Progress per document, keyed on the summary fields that can change it (see `progressKey`),
    /// so an unchanged document is never decoded twice. `@ObservationIgnored`: it is a cache behind
    /// `progress`, not state a view reads.
    @ObservationIgnored private var progressCache: [UUID: (key: DocumentSummary, value: DocumentProgress)] = [:]
    /// Glimpses per document (`glimpse(for:)`), keyed on the fields that move one, for the same
    /// reason: a chapter decode per Home row per refresh would be the cost this cache exists to avoid.
    @ObservationIgnored private var glimpseCache: [UUID: (key: GlimpseKey, value: RowGlimpse)] = [:]

    /// What decides what a glimpse shows: the chapter read, where in it the resume position lands,
    /// and whether the chapters are about to be re-derived under it.
    private struct GlimpseKey: Hashable {
        var chapterIndex: Int
        var resumePosition: Position?
        var isStale: Bool
        var utteranceCount: Int
    }

    public init(library: Library) { self.library = library }

    // MARK: Derived lists

    /// Queued, unfinished documents in user order.
    public var queue: [DocumentSummary] {
        summaries.filter { $0.queueOrder != nil && !$0.isFinished }.sorted { ($0.queueOrder ?? 0) < ($1.queueOrder ?? 0) }
    }

    /// Finished documents, most recently played first.
    public var finished: [DocumentSummary] {
        summaries.filter(\.isFinished).sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    /// Everything imported, newest first, whatever its queue state: books, PDFs and articles
    /// alike. Spec §2.3 kept articles off the Collection and on Home; with Home down to the three
    /// last played (2026-09-09) the Collection is the only shelf an article could stay on, and the
    /// owner asked for Text and Links filters there.
    public var collection: [DocumentSummary] {
        summaries
    }

    public var visibleRows: [DocumentSummary] { queueView == .queue ? queue : finished }
    public var isQueueEmpty: Bool { queue.isEmpty }

    /// "14 items · ~6h 20m": remaining time across the Queue, `~` while any of it is an estimate.
    public var queueSubtitle: String {
        let rows = queue
        guard !rows.isEmpty else { return DurationFormatter.items(0) }
        var seconds: TimeInterval = 0
        var approximate = false
        for row in rows {
            if let p = progress[row.id] {
                seconds += p.remainingSeconds
                approximate = approximate || p.isApproximate
            } else {
                seconds += row.totalSeconds
                approximate = approximate || !row.isFullyRendered
            }
        }
        return "\(DurationFormatter.items(rows.count)) · \(DurationFormatter.long(seconds, approximate: approximate))"
    }

    public func progress(for id: UUID) -> DocumentProgress? { progress[id] }

    // MARK: Refresh

    public func refresh() async {
        do {
            let all = try await library.store.summaries()
            var next: [UUID: DocumentProgress] = [:]
            var cache: [UUID: (key: DocumentSummary, value: DocumentProgress)] = [:]
            for s in all where s.queueOrder != nil || s.isFinished {
                let key = progressKey(s)
                if let hit = progressCache[s.id], hit.key == key {           // nothing that moves progress changed
                    next[s.id] = hit.value
                    cache[s.id] = hit
                    continue
                }
                if let stored = DocumentProgress.fromSummary(s) {                // the row says where it is
                    next[s.id] = stored
                    cache[s.id] = (key, stored)
                } else if let timeline = try await library.currentTimeline(s.id) {
                    let computed = DocumentProgress.compute(summary: s, timeline: timeline)
                    next[s.id] = computed
                    cache[s.id] = (key, computed)
                }
            }
            summaries = all
            progress = next
            progressCache = cache                                            // rebuilt, so deleted ids drop out
            let ids = Set(all.map(\.id))
            glimpseCache = glimpseCache.filter { ids.contains($0.key) }      // a stale key re-decodes on its own
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    /// Where the reader is inside the resume chapter — a few lines of its text from the resume
    /// position on, and how far through the chapter that is — for the Home row. Decodes that one
    /// chapter from the store; cached per document against the fields that move it. Nil when the
    /// chapter cannot be read or has no utterances.
    public func glimpse(for summary: DocumentSummary) async -> RowGlimpse? {
        let chapterIndex = progress[summary.id]?.chapterIndex ?? summary.resumeChapterIndex ?? 0
        let key = GlimpseKey(chapterIndex: chapterIndex, resumePosition: summary.document.resumePosition,
                             isStale: summary.isStale, utteranceCount: summary.utteranceCount)
        if let hit = glimpseCache[summary.id], hit.key == key { return hit.value }
        guard let chapter = try? await library.store.chapter(chapterIndex, of: summary.id),
              !chapter.utterances.isEmpty else { return nil }
        // Resolved against the one chapter alone: the resolver walks utterances, and this is the
        // only chapter the position can land in, so the rest of the document stays undecoded — and
        // the same one-chapter index makes its times chapter-relative for free.
        let timeline = Timeline(chapters: [chapter])
        let index = TimeIndex(timeline)
        let playhead = index.clamp(summary.document.resumePosition.map { PositionResolver.resolve($0, in: timeline) }
                                   ?? Playhead(utteranceIndex: 0))
        let start = min(max(0, playhead.utteranceIndex), chapter.utterances.count - 1)
        var text = ""
        for utterance in chapter.utterances[start...] {
            text += text.isEmpty ? utterance.source : " " + utterance.source
            if text.count >= Self.excerptLength { break }
        }
        let excerpt = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")   // one line, trimmed
        let glimpse = RowGlimpse(excerpt: excerpt.isEmpty ? nil : excerpt,
                                 chapterElapsedSeconds: index.time(at: playhead), chapterTotalSeconds: index.totalDuration)
        glimpseCache[summary.id] = (key, glimpse)
        return glimpse
    }

    /// The glimpse's text alone.
    public func excerpt(for summary: DocumentSummary) async -> String? { await glimpse(for: summary)?.excerpt }

    /// Enough source text for a row's few lines; the joined text stops at the utterance that crosses it.
    private static let excerptLength = 240

    /// The summary reduced to what `DocumentProgress.compute` actually reads: queue position, last
    /// played, and finished state move rows around but never change a row's progress, so an archive
    /// or a move must not cost a chapter decode.
    private func progressKey(_ summary: DocumentSummary) -> DocumentSummary {
        var key = summary
        key.queueOrder = nil
        key.lastPlayedAt = nil
        key.isFinished = false
        return key
    }

    // MARK: Actions (each ends with a refresh so the lists are always the store's truth)

    public func archive(_ id: UUID) async { await perform { try await self.library.store.setQueued(id, false) } }

    public func enqueue(_ id: UUID) async { await perform { try await self.library.store.setQueued(id, true) } }

    public func move(_ id: UUID, to index: Int) async { await perform { try await self.library.store.moveInQueue(id, to: index) } }

    /// How many books Home keeps under Continue Listening.
    public static let recentLimit = 3

    /// Home is the books played most recently, latest first, at most `recentLimit` of them (owner's
    /// rule, 2026-09-09: there is no queue a reader manages). Called when playback starts: the book
    /// goes to the top — back out of finished if it was — and whatever falls past the limit leaves.
    /// A no-op, with no refresh, when the book is already on top and nothing needs trimming.
    public func notePlaying(_ id: UUID) async {
        guard let summary = summaries.first(where: { $0.id == id }) else { return }
        let rows = queue
        if rows.first?.id == id, rows.count <= Self.recentLimit { return }
        await perform {
            if summary.isFinished { try await self.library.store.finish(id, false) }
            try await self.library.store.setQueued(id, true)
            try await self.library.store.moveInQueue(id, to: 0)
            for document in try await self.library.store.queue().dropFirst(Self.recentLimit) {
                try await self.library.store.setQueued(document.id, false)
            }
        }
    }

    /// Finished leaves the Queue; un-finishing puts the document back at the end (spec §2.4.5 context menu).
    public func markFinished(_ id: UUID, _ finished: Bool) async {
        await perform { try await self.library.store.finish(id, finished) }
    }

    public func delete(_ id: UUID) async { await perform { try await self.library.delete(id) } }

    private func perform(_ action: @MainActor @Sendable () async throws -> Void) async {
        do {
            try await action()
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
        await refresh()
    }
}
