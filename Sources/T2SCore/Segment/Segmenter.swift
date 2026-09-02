import Foundation
import NaturalLanguage

public struct Segmenter: Sendable {
    public static let version = Versions.segmenter
    /// Sentences longer than this (UTF-16 units of source) split at clause boundaries.
    public var maxUtteranceLength: Int
    public var normalizer: TextNormalizer

    public init(normalizer: TextNormalizer, maxUtteranceLength: Int = 300) {
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

    /// Trimmed sentences with their UTF-16 offset in `text`.
    private func sentences(in text: String) -> [(String, Int)] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [(String, Int)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let raw = text[range]
            let lead = raw.prefix(while: { $0.isWhitespace }).count
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let leadUTF16 = String(raw.prefix(lead)).utf16.count
                out.append((trimmed, range.lowerBound.utf16Offset(in: text) + leadUTF16))
            }
            return true
        }
        return out
    }

    /// Splits `sentence` into pieces ≤ maxUtteranceLength at the last clause boundary before the limit,
    /// falling back to the last space, then to a hard cut. Offsets are UTF-16 into the block.
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
                cut = ns.rangeOfCharacter(from: .whitespaces, options: .backwards, range: window).location
            }
            if cut == NSNotFound || cut <= start { cut = start + maxUtteranceLength }
            let piece = ns.substring(with: NSRange(location: start, length: cut - start))
            let lead = piece.prefix(while: { $0.isWhitespace }).count
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { pieces.append((trimmed, offset + start + String(piece.prefix(lead)).utf16.count)) }
            start = cut
        }
        let tail = ns.substring(from: start)
        let lead = tail.prefix(while: { $0.isWhitespace }).count
        let trimmed = tail.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { pieces.append((trimmed, offset + start + String(tail.prefix(lead)).utf16.count)) }
        return pieces
    }
}
