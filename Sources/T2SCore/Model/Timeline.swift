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

public struct Timeline: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var segmenterVersion: Int
    public var normalizerVersion: Int
    public var chapters: [Chapter]

    public init(chapters: [Chapter],
                schemaVersion: Int = Versions.schema,
                segmenterVersion: Int = Versions.segmenter,
                normalizerVersion: Int = Versions.normalizer) {
        self.chapters = chapters
        self.schemaVersion = schemaVersion
        self.segmenterVersion = segmenterVersion
        self.normalizerVersion = normalizerVersion
    }

    public var utteranceCount: Int { chapters.reduce(0) { $0 + $1.utterances.count } }

    /// Precondition: `c` is a valid chapter index.
    public func utteranceRange(ofChapter c: Int) -> Range<Int> {
        precondition(chapters.indices.contains(c), "chapter \(c) out of range (\(chapters.count))")
        let start = chapters[..<c].reduce(0) { $0 + $1.utterances.count }
        return start..<(start + chapters[c].utterances.count)
    }

    public func chapterIndex(forUtterance i: Int) -> Int? {
        guard i >= 0 else { return nil }
        var start = 0
        for (c, ch) in chapters.enumerated() {
            if i < start + ch.utterances.count { return c }
            start += ch.utterances.count
        }
        return nil
    }

    private func location(ofUtterance i: Int) -> (chapter: Int, local: Int) {
        guard let c = chapterIndex(forUtterance: i) else {
            preconditionFailure("utterance \(i) out of range (\(utteranceCount))")
        }
        return (c, i - utteranceRange(ofChapter: c).lowerBound)
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
