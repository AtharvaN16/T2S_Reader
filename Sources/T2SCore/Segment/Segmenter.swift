import Foundation
import NaturalLanguage

public struct Segmenter: Sendable {
    public static let version = Versions.segmenter
    /// Sentences longer than this (UTF-16 units of source) split at clause boundaries.
    public private(set) var maxUtteranceLength: Int
    public var normalizer: TextNormalizer

    public init(normalizer: TextNormalizer, maxUtteranceLength: Int = 300) {
        precondition(maxUtteranceLength >= 2, "maxUtteranceLength must be at least 2")
        self.normalizer = normalizer
        self.maxUtteranceLength = maxUtteranceLength
    }

    public func segment(_ block: SourceBlock) -> [Utterance] {
        var result: [Utterance] = []
        for (text, offset) in sentences(in: block.text) {
            for (piece, pieceOffset) in split(text, at: offset) {
                let normalized = normalizer.normalize(piece)
                guard !normalized.spoken.isEmpty else { continue }
                var position = block.position
                position.charOffset = block.position.charOffset.map { $0 + pieceOffset }
                result.append(Utterance(
                    position: position,
                    source: piece,
                    spoken: normalized.spoken,
                    spans: normalized.spans,
                    duration: .estimated(DurationEstimator.estimate(spoken: normalized.spoken))
                ))
            }
        }
        return result
    }

    /// Trims whitespace and newlines from both ends of `s`, returning the trimmed text and the
    /// UTF-16 offset of its first character given that `s` starts at `offset`; nil when empty.
    /// The one place leading whitespace is measured, so counting and trimming cannot disagree.
    static func trimmed(_ s: String, at offset: Int) -> (String, Int)? {
        let ws = CharacterSet.whitespacesAndNewlines
        let t = s.trimmingCharacters(in: ws)
        guard !t.isEmpty else { return nil }
        let lead = s.unicodeScalars.prefix(while: { ws.contains($0) }).reduce(0) { $0 + $1.utf16.count }
        return (t, offset + lead)
    }

    /// Trimmed sentences with their UTF-16 offset in `text`.
    private func sentences(in text: String) -> [(String, Int)] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [(String, Int)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if let piece = Self.trimmed(String(text[range]), at: range.lowerBound.utf16Offset(in: text)) {
                out.append(piece)
            }
            return true
        }
        return out
    }

    /// Splits `sentence` into pieces ≤ maxUtteranceLength at the last clause boundary before the limit,
    /// falling back to the last whitespace, then to a hard cut that never divides a surrogate pair.
    /// Offsets are UTF-16 into the block.
    private func split(_ sentence: String, at offset: Int) -> [(String, Int)] {
        let ns = sentence as NSString
        guard ns.length > maxUtteranceLength else { return [(sentence, offset)] }
        var pieces: [(String, Int)] = []
        var start = 0
        let clause = CharacterSet(charactersIn: ";:,—–")
        while ns.length - start > maxUtteranceLength {
            let window = NSRange(location: start, length: maxUtteranceLength)
            var cut = ns.rangeOfCharacter(from: clause, options: .backwards, range: window).location
            if cut != NSNotFound && cut > start { cut += 1 }
            if cut == NSNotFound || cut <= start {
                cut = ns.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards, range: window).location
            }
            if cut == NSNotFound || cut <= start {
                cut = start + maxUtteranceLength
                if cut - 1 > start && CFStringIsSurrogateHighCharacter(ns.character(at: cut - 1)) { cut -= 1 }
            }
            if let piece = Self.trimmed(ns.substring(with: NSRange(location: start, length: cut - start)), at: offset + start) {
                pieces.append(piece)
            }
            start = cut
        }
        if let piece = Self.trimmed(ns.substring(from: start), at: offset + start) {
            pieces.append(piece)
        }
        return pieces
    }
}
