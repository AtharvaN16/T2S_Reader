import Foundation

public struct HighlightRange: Hashable, Sendable {
    public var utteranceIndex: Int
    /// The utterance's start position; combine with `sourceRange` to decorate the document.
    public var position: Position
    /// UTF-16 range within the utterance's `source`.
    public var sourceRange: Range<Int>
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
            let fraction = u.duration.seconds > 0 ? max(0, min(0.999, ph.offset / u.duration.seconds)) : 0
            let i = Int(Double(all.count) * fraction)
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
