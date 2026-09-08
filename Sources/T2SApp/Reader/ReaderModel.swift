import Foundation
import Observation
import T2SCore
import T2SLibrary

/// The Reader page's state over the shared player (spec §2.3: both observe the same coordinator).
/// Following = auto-scroll keeps the active line in view; a manual scroll suspends it; a tap on a
/// word seeks there via `seek(toUtterance:sourceOffset:)` and re-engages following.
@MainActor
@Observable
public final class ReaderModel {
    public let player: PlayerModel
    public private(set) var isFollowing = true

    public init(player: PlayerModel) {
        self.player = player
    }

    public var activeHighlight: HighlightRange? { player.coordinator.highlight }
    public var isCatchingUp: Bool { player.isCatchingUp }

    public var chapterTitle: String {
        guard let timeline = player.coordinator.timeline,
              let index = player.chapterIndex,
              timeline.chapters.indices.contains(index) else {
            return player.current?.document.title ?? ""
        }
        return timeline.chapters[index].title
    }

    public func suspendFollowing() {
        isFollowing = false
    }

    public func resumeFollowing() {
        isFollowing = true
    }

    /// Tap on a word the Reader drew itself (spec 2026-09-07 §5): seek to that word's timing inside
    /// its utterance and re-engage following. False when the index is out of range.
    public func seek(toUtterance index: Int, sourceOffset: Int) async -> Bool {
        guard let timeline = player.coordinator.timeline,
              let playhead = Self.playhead(utteranceIndex: index, sourceOffset: sourceOffset, in: timeline)
        else { return false }
        await player.coordinator.seek(to: playhead)
        isFollowing = true
        return true
    }

    /// Where an offset into an utterance's `source` lands: the start of the word whose timing covers
    /// it, or the utterance start when it carries no timings yet. Offsets are clamped into the source.
    public static func playhead(utteranceIndex: Int, sourceOffset: Int, in timeline: Timeline) -> Playhead? {
        guard utteranceIndex >= 0, utteranceIndex < timeline.utteranceCount else { return nil }
        let utterance = timeline[utterance: utteranceIndex]
        guard let timings = utterance.wordTimings, !timings.isEmpty else { return Playhead(utteranceIndex: utteranceIndex) }
        let sourceLength = utterance.source.utf16.count
        let clamped = min(max(0, sourceOffset), max(0, sourceLength - 1))
        let spoken = utterance.normalized.spokenRange(forSource: clamped ..< min(sourceLength, clamped + 1)).lowerBound
        let word = timings.first { $0.spokenRange.contains(spoken) }
            ?? timings.first { $0.spokenRange.lowerBound >= spoken }
        return Playhead(utteranceIndex: utteranceIndex, offset: word?.start ?? 0)
    }
}
