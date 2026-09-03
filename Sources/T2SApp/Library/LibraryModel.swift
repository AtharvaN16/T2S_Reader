import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

public enum QueueView: Hashable, Sendable { case queue, finished }

/// The Queue and Collection pages' state (spec §2.3, §2.4.5). Reads summaries from the store and
/// per-document progress through `Library.currentTimeline`, which decodes the stored chapters but
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
                if let timeline = try await library.currentTimeline(s.id) {
                    let computed = DocumentProgress.compute(summary: s, timeline: timeline)
                    next[s.id] = computed
                    cache[s.id] = (key, computed)
                }
            }
            summaries = all
            progress = next
            progressCache = cache                                            // rebuilt, so deleted ids drop out
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

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
