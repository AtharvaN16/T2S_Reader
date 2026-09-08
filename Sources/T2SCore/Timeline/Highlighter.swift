import Foundation

public struct HighlightRange: Hashable, Sendable {
    public var utteranceIndex: Int
    /// The utterance's start position; combine with `sourceRange` to decorate the document.
    public var position: Position
    /// UTF-16 range within the utterance's `source`.
    public var sourceRange: Range<Int>

    public init(utteranceIndex: Int, position: Position, sourceRange: Range<Int>) {
        self.utteranceIndex = utteranceIndex
        self.position = position
        self.sourceRange = sourceRange
    }
}

public enum Highlighter {
    static let word = Pattern("\\S+")

    public static func highlight(at ph: Playhead, in t: Timeline) -> HighlightRange? {
        guard ph.utteranceIndex >= 0, ph.utteranceIndex < t.utteranceCount else { return nil }
        let u = t[utterance: ph.utteranceIndex]
        let spokenWords: [Range<Int>]
        if let timings = u.wordTimings, !timings.isEmpty {
            let i = timings.lastIndex(where: { $0.start <= ph.offset }) ?? 0
            spokenWords = Array(timings[i...].map(\.spokenRange))
        } else {
            let ns = u.spoken as NSString
            let all = word.regex.matches(in: u.spoken, range: NSRange(location: 0, length: ns.length))
                .map { $0.range.location..<($0.range.location + $0.range.length) }
            guard !all.isEmpty else { return nil }
            let target = u.spokenOffset(atTime: ph.offset)
            // No word ends after `target` once playback has run past the last word (target lands
            // exactly at the end of `spoken`): clamp to the last word rather than reporting nil.
            let i = all.firstIndex(where: { $0.upperBound > target }) ?? all.count - 1
            spokenWords = Array(all[i...])
        }
        let n = u.normalized
        for w in spokenWords {
            let src = n.sourceRange(forSpoken: w)
            if !src.isEmpty {
                return HighlightRange(utteranceIndex: ph.utteranceIndex, position: u.position, sourceRange: src)
            }
        }
        return nil
    }
}
