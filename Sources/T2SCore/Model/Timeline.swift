import Foundation

public struct Chapter: Codable, Hashable, Sendable {
    public var title: String
    public var position: Position
    public var utterances: [Utterance]

    public init(title: String, position: Position, utterances: [Utterance]) {
        self.title = title
        self.position = position
        self.utterances = utterances
    }
}

public struct Timeline: Hashable, Sendable {
    public var schemaVersion: Int
    public var segmenterVersion: Int
    public var normalizerVersion: Int
    public var chapters: [Chapter] {
        didSet { chapterStarts = Self.starts(of: chapters) }
    }
    /// The flat utterance index each chapter starts at, in chapter order, then the total: one entry
    /// more than there are chapters, and an empty chapter repeats the next one's start. Derived
    /// from `chapters` and kept in step with every mutation of it, so `utteranceCount`, a chapter's
    /// range and the chapter an utterance is in are a lookup or a binary search — the coordinator
    /// asks the last two once per utterance on a load, a hand-off and every `.rendered` event, on
    /// the main actor, and walking the chapters for each made a big book's open a visible stall.
    public private(set) var chapterStarts: [Int]

    /// Versions default to the current ones (`Versions`); a decoded timeline carries the ones it
    /// was derived under, and a mismatch marks it stale (spec §3.7.4).
    public init(chapters: [Chapter],
                schemaVersion: Int = Versions.schema,
                segmenterVersion: Int = Versions.segmenter,
                normalizerVersion: Int = Versions.normalizer) {
        self.chapters = chapters
        self.chapterStarts = Self.starts(of: chapters)
        self.schemaVersion = schemaVersion
        self.segmenterVersion = segmenterVersion
        self.normalizerVersion = normalizerVersion
    }

    private static func starts(of chapters: [Chapter]) -> [Int] {
        var starts: [Int] = []
        starts.reserveCapacity(chapters.count + 1)
        var next = 0
        for chapter in chapters {
            starts.append(next)
            next += chapter.utterances.count
        }
        starts.append(next)
        return starts
    }

    public var utteranceCount: Int { chapterStarts[chapterStarts.count - 1] }

    /// Precondition: `c` is a valid chapter index.
    public func utteranceRange(ofChapter c: Int) -> Range<Int> {
        precondition(chapters.indices.contains(c), "chapter \(c) out of range (\(chapters.count))")
        return chapterStarts[c]..<chapterStarts[c + 1]
    }

    /// The chapter holding utterance `i`: the last chapter whose start is at or before it. An
    /// empty chapter shares its start with the one after, so that rule never lands on an empty one
    /// — the chapter after it starts on the same index and is later.
    public func chapterIndex(forUtterance i: Int) -> Int? {
        guard i >= 0, i < utteranceCount else { return nil }
        var low = 0
        var high = chapters.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if chapterStarts[mid] <= i { low = mid } else { high = mid - 1 }
        }
        return low
    }

    private func location(ofUtterance i: Int) -> (chapter: Int, local: Int) {
        guard let c = chapterIndex(forUtterance: i) else {
            preconditionFailure("utterance \(i) out of range (\(utteranceCount))")
        }
        return (c, i - chapterStarts[c])
    }

    public subscript(utterance i: Int) -> Utterance {
        get { let l = location(ofUtterance: i); return chapters[l.chapter].utterances[l.local] }
        set { let l = location(ofUtterance: i); chapters[l.chapter].utterances[l.local] = newValue }
    }

    /// Derived, display-only (spec §3.2): sum of preceding durations at 1x.
    /// `i == utteranceCount` is allowed and yields the total duration (the end of the timeline).
    public func startTime(ofUtterance i: Int) -> TimeInterval {
        precondition(i >= 0 && i <= utteranceCount, "utterance \(i) out of range (\(utteranceCount))")
        var t: TimeInterval = 0
        var n = 0
        for ch in chapters {
            for u in ch.utterances {
                if n == i { return t }
                t += u.duration.seconds
                n += 1
            }
        }
        return t
    }

    public var totalDuration: TimeInterval {
        chapters.reduce(0) { $0 + $1.utterances.reduce(0) { $0 + $1.duration.seconds } }
    }

    public var isFullyRendered: Bool {
        chapters.allSatisfy { $0.utterances.allSatisfy { $0.duration.isActual && $0.audioRef != nil } }
    }
}

/// The four fields it always encoded: `chapterStarts` is derived, so it is neither written nor
/// expected, and a timeline decoded from any earlier encoding rebuilds it.
extension Timeline: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, segmenterVersion, normalizerVersion, chapters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(chapters: try container.decode([Chapter].self, forKey: .chapters),
                  schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
                  segmenterVersion: try container.decode(Int.self, forKey: .segmenterVersion),
                  normalizerVersion: try container.decode(Int.self, forKey: .normalizerVersion))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(segmenterVersion, forKey: .segmenterVersion)
        try container.encode(normalizerVersion, forKey: .normalizerVersion)
        try container.encode(chapters, forKey: .chapters)
    }
}
