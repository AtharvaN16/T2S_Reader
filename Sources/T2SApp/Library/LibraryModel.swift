import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

public enum QueueView: Hashable, Sendable { case queue, finished }

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
    /// Excerpts per document (`excerpt(for:)`), keyed on the fields that move one, for the same
    /// reason: a chapter decode per Home row per refresh would be the cost this cache exists to avoid.
    @ObservationIgnored private var excerptCache: [UUID: (key: ExcerptKey, value: String)] = [:]

    /// What decides which utterances an excerpt shows: the chapter read, where in it the resume
    /// position lands, and whether the chapters are about to be re-derived under it.
    private struct ExcerptKey: Hashable {
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

    /// Every EPUB and PDF, newest first, whatever its queue state (spec §2.3).
    public var collection: [DocumentSummary] {
        summaries.filter { $0.document.sourceType == .epub || $0.document.sourceType == .pdf }
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
            excerptCache = excerptCache.filter { ids.contains($0.key) }      // a stale key re-decodes on its own
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    /// A few lines of text from where the reader is in the document — the utterance at the resume
    /// position and the ones after it, for the Home row's "where we are in the story" line.
    /// Decodes one chapter from the store; cached per document against the fields that move it.
    public func excerpt(for summary: DocumentSummary) async -> String? {
        let chapterIndex = progress[summary.id]?.chapterIndex ?? summary.resumeChapterIndex ?? 0
        let key = ExcerptKey(chapterIndex: chapterIndex, resumePosition: summary.document.resumePosition,
                             isStale: summary.isStale, utteranceCount: summary.utteranceCount)
        if let hit = excerptCache[summary.id], hit.key == key { return hit.value }
        guard let chapter = try? await library.store.chapter(chapterIndex, of: summary.id),
              !chapter.utterances.isEmpty else { return nil }
        // Resolved against the one chapter alone: the resolver walks utterances, and this is the
        // only chapter the position can land in, so the rest of the document stays undecoded.
        let timeline = Timeline(chapters: [chapter])
        let resolved = summary.document.resumePosition.map { PositionResolver.resolve($0, in: timeline).utteranceIndex } ?? 0
        let start = min(max(0, resolved), chapter.utterances.count - 1)
        var text = ""
        for utterance in chapter.utterances[start...] {
            text += text.isEmpty ? utterance.source : " " + utterance.source
            if text.count >= Self.excerptLength { break }
        }
        let excerpt = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")   // one line, trimmed
        guard !excerpt.isEmpty else { return nil }
        excerptCache[summary.id] = (key, excerpt)
        return excerpt
    }

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
