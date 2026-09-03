import Foundation
import Observation
import T2SCore
import T2SLibrary

/// The Reader page's state over the shared player (spec §2.3: both observe the same coordinator).
/// Following = auto-scroll keeps the active line in view; a manual scroll suspends it; a tap on a
/// sentence seeks there and re-engages following.
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

    /// Tap a sentence → seek there (spec §2.4.5). False when the tap matches no utterance.
    public func seek(to hit: SourceHit) async -> Bool {
        guard let timeline = player.coordinator.timeline,
              let index = Self.utteranceIndex(for: hit, in: timeline) else {
            return false
        }
        await player.coordinator.seek(to: Playhead(utteranceIndex: index))
        isFollowing = true
        return true
    }

    /// Whitespace runs collapse to one space and the ends are trimmed, the way Readium's segments are.
    public static func normalized(_ string: String) -> String {
        string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The utterance under a tap: same resource, `source` contained in the block's normalized text,
    /// and the tap's normalized offset inside it (or the nearest following one; PDF: first utterance
    /// of the tapped page).
    public static func utteranceIndex(for hit: SourceHit, in timeline: Timeline) -> Int? {
        var index = 0
        var candidates: [(index: Int, utterance: Utterance)] = []
        for chapter in timeline.chapters {
            for utterance in chapter.utterances {
                if utterance.position.resourceHref == hit.resourceHref {
                    candidates.append((index, utterance))
                }
                index += 1
            }
        }
        guard !candidates.isEmpty else { return nil }

        if let page = hit.pageIndex {
            let pages = candidates.map(\.utterance.position.progression)
            guard let count = pageCount(from: pages) else { return nil }
            let target = Double(page) / Double(count)
            return candidates.first { abs($0.utterance.position.progression - target) < 1e-9 }?.index
        }

        let block = normalized(hit.blockText)
        guard !block.isEmpty else { return nil }
        let end = Swift.min(Swift.max(0, hit.offsetInBlock), hit.blockText.utf16.count)
        let prefix = String(decoding: hit.blockText.utf16.prefix(end), as: UTF16.self)
        let offset = normalized(prefix).utf16.count
        let blockText = block as NSString
        var located: [(index: Int, start: Int, length: Int)] = []
        for candidate in candidates {
            let source = normalized(candidate.utterance.source)
            guard !source.isEmpty else { continue }
            let range = blockText.range(of: source)
            if range.location != NSNotFound {
                located.append((candidate.index, range.location, range.length))
            }
        }
        guard !located.isEmpty else { return nil }
        if let inside = located.first(where: { $0.start <= offset && offset < $0.start + $0.length }) {
            return inside.index
        }
        // A caret in collapsed whitespace belongs to the sentence about to be read. This agrees
        // with Readium's tap behavior and gives the following utterance at sentence boundaries.
        if let following = located.filter({ $0.start >= offset }).min(by: { $0.start < $1.start }) {
            return following.index
        }
        return located.max(by: { $0.start < $1.start })?.index
    }

    /// PDF positions are `pageIndex / pageCount`; the count is recoverable from the smallest positive step.
    private static func pageCount(from progressions: [Double]) -> Int? {
        let distinct = Set(progressions).sorted()
        guard distinct.count > 1 else { return distinct.first == 0 ? 1 : nil }
        let step = zip(distinct, distinct.dropFirst()).map { $1 - $0 }.min() ?? 0
        guard step > 0 else { return nil }
        return Int((1 / step).rounded())
    }
}
