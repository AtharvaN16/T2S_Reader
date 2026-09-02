import Foundation
import Observation
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
}

/// The UI's one view of playback (spec §3): a thin, observable bridge over `PlaybackCoordinator`
/// plus the strings and derived shapes the player sheet and mini-player draw. It also owns the one
/// piece of persistence the coordinator does not: writing rendered chapters (actual durations, word
/// timings, audio refs) back to the store, on pause, on switching documents, and on demand.
@MainActor
@Observable
public final class PlayerModel {
    public let coordinator: PlaybackCoordinator
    public private(set) var current: DocumentSummary?
    public private(set) var renderError: String?

    private let library: Library
    /// Hash of each chapter as last written, to skip unchanged chapters on the next persist.
    private var persistedChapterHashes: [Int] = []

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
        let index = coordinator.timeIndex
        let now = elapsed
        return timeline.chapters.indices.map { c in
            let range = timeline.utteranceRange(ofChapter: c)
            let start = index.startTime(ofUtterance: range.lowerBound)
            let end = index.startTime(ofUtterance: range.upperBound)
            let duration = end - start
            let fraction = duration > 0 ? min(1, max(0, (now - start) / duration)) : 0
            return ChapterEntry(index: c, title: timeline.chapters[c].title, startSeconds: start, durationSeconds: duration, fraction: fraction)
        }
    }

    public var scrubber: ScrubberModel {
        guard let timeline = coordinator.timeline else { return ScrubberModel(tickCount: 48, renderedTicks: Array(repeating: false, count: 48), fraction: 0) }
        return ScrubberModel.make(timeline: timeline, timeIndex: coordinator.timeIndex, playhead: coordinator.playhead)
    }

    // MARK: Loading

    /// Loads a document (re-deriving a stale timeline on the way) and optionally starts playing.
    /// Whatever was loaded before is persisted first.
    public func load(_ summary: DocumentSummary, play: Bool) async {
        await persistRenderedChapters()
        do {
            guard let timeline = try await library.timelineForPlayback(summary.id) else {
                renderError = "Document is missing"
                return
            }
            coordinator.load(summary.document, timeline: timeline)
            current = summary
            persistedChapterHashes = timeline.chapters.map(\.hashValue)
            renderError = nil
            if play { await coordinator.play() }
        } catch {
            renderError = "\(error)"
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

    /// Drive from a 10 Hz timer while playing (spec §3: the coordinator polls the player clock).
    public func tick() {
        coordinator.tick()
        if let error = coordinator.lastRenderError { renderError = error }
    }

    // MARK: Persistence of phase 2

    /// Writes chapters whose utterances changed since the last write (actual durations, word
    /// timings, audio refs from `.rendered` events). Cheap when nothing changed.
    public func persistRenderedChapters() async {
        guard let current, let timeline = coordinator.timeline else { return }
        for (c, chapter) in timeline.chapters.enumerated() {
            let hash = chapter.hashValue
            if c < persistedChapterHashes.count, persistedChapterHashes[c] == hash { continue }
            do {
                try await library.store.saveChapter(chapter, at: c, of: current.id)
                if c < persistedChapterHashes.count { persistedChapterHashes[c] = hash } else { persistedChapterHashes.append(hash) }
            } catch {
                renderError = "\(error)"
            }
        }
    }
}
