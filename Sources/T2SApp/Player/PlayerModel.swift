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
        timeline.chapters.indices.map { c in
            let range = timeline.utteranceRange(ofChapter: c)
            let start = timeIndex.startTime(ofUtterance: range.lowerBound)
            let end = timeIndex.startTime(ofUtterance: range.upperBound)
            let duration = end - start
            let fraction = duration > 0 ? min(1, max(0, (elapsed - start) / duration)) : 0
            return ChapterEntry(index: c, title: timeline.chapters[c].title, startSeconds: start, durationSeconds: duration, fraction: fraction)
        }
    }
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
    /// Load or persistence failures from this model; cleared by the next successful load or persist.
    public private(set) var localError: String?
    /// The coordinator's last render error, else this model's own; the coordinator clears its error on load.
    public var renderError: String? { coordinator.lastRenderError ?? localError }

    private let library: Library
    private static let log = Logger(subsystem: "com.t2s.reader", category: "playback")
    /// Hash of each chapter as last written, to skip unchanged chapters on the next persist.
    private var persistedChapterHashes: [Int] = []
    /// The tick array is O(timeline) and the player sheet's body runs at 10 Hz while playing, so it
    /// is a cache invalidated by `coordinator.timelineRevision`, not a computed property.
    /// `@ObservationIgnored`: filling it from `scrubber`'s getter must not invalidate the body that
    /// is reading it.
    @ObservationIgnored private var tickCache: (revision: Int, ticks: [Bool])?

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
    public var isTotalApproximate: Bool { !(coordinator.timeline?.isFullyRendered ?? false) }
    public var elapsedText: String { DurationFormatter.clock(elapsed) }
    public var remainingText: String { DurationFormatter.remaining(total - elapsed, approximate: isTotalApproximate) }
    public var totalText: String { (isTotalApproximate ? "~" : "") + DurationFormatter.clock(total) }
    public var chapterIndex: Int? { coordinator.timeline?.chapterIndex(forUtterance: coordinator.playhead.utteranceIndex) }

    public var chapters: [ChapterEntry] {
        guard let timeline = coordinator.timeline else { return [] }
        return ChapterEntry.entries(timeline: timeline, timeIndex: coordinator.timeIndex, elapsed: elapsed)
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
            document.voiceID = await voiceRouting.effectiveVoiceID(requestedVoiceID)
            if let effective = document.voiceID, effective != requestedVoiceID {
                // The route, never the voice: a voice ID can carry a provider's voice name, and the
                // document's title must never reach the log.
                let route = String(requestedVoiceID.prefix { $0 != ":" })
                Self.log.notice("voice route fallback: \(route, privacy: .public) → \(effective, privacy: .public)")
            }
            coordinator.load(document, timeline: timeline)
            current = summary
            persistedChapterHashes = timeline.chapters.map(\.hashValue)
            localError = nil
            if play { await coordinator.play() }
        } catch {
            localError = "\(error)"
        }
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

    public func setRate(_ rate: Double) { coordinator.setRate(rate) }

    public func renderWholeDocument() { coordinator.renderWholeDocument() }

    /// A bookmark at the playhead, persisted as a `Position` (spec §3.2). False when nothing is loaded.
    public func addBookmark() async -> Bool {
        guard let current, let timeline = coordinator.timeline, timeline.utteranceCount > 0 else { return false }
        let position = PositionResolver.position(for: coordinator.playhead, in: timeline)
        do {
            try await library.store.add(Bookmark(documentID: current.id, position: position))
            return true
        } catch {
            localError = "\(error)"
            return false
        }
    }

    /// Drive from a 10 Hz timer while playing (spec §3: the coordinator polls the player clock).
    public func tick() {
        coordinator.tick()
    }

    // MARK: Persistence of phase 2

    /// Writes chapters whose utterances changed since the last write (actual durations, word
    /// timings, audio refs from `.rendered` events). Cheap when nothing changed.
    public func persistRenderedChapters() async {
        guard let current, let timeline = coordinator.timeline else { return }
        var failed = false
        for (c, chapter) in timeline.chapters.enumerated() {
            let hash = chapter.hashValue
            if c < persistedChapterHashes.count, persistedChapterHashes[c] == hash { continue }
            do {
                try await library.store.saveChapter(chapter, at: c, of: current.id)
                if c < persistedChapterHashes.count { persistedChapterHashes[c] = hash } else { persistedChapterHashes.append(hash) }
            } catch {
                localError = "\(error)"
                failed = true
            }
        }
        if !failed { localError = nil }
    }
}
