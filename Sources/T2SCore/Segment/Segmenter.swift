import Foundation
import NaturalLanguage

public struct Segmenter: Sendable {
    public static let version = Versions.segmenter
    /// Sentences longer than this (UTF-16 units of source) split at clause boundaries.
    public private(set) var maxUtteranceLength: Int
    /// Consecutive sentences of one block are packed into one utterance while the packed source stays
    /// within this many UTF-16 units; 0 keeps one sentence per utterance.
    ///
    /// Why pack at all: an utterance is one synthesis call, and Kokoro ends every call with a long
    /// predicted pause and starts the next one cold — about 800 ms of dead air after every sentence,
    /// and the same on the MLX reference, so it is the model's behaviour for short inputs. Two or
    /// three sentences in one call read as continuous speech with natural pauses between them
    /// (`spikes/findings/2026-09-05-coreml-audio-quality.md`). Why 160: the Core ML engine's one-call
    /// cap is 176 phoneme ids and the probe measured 0.98 ids per source character, so 160 leaves a
    /// margin for phoneme-dense text — a packed utterance is almost always one call, and the seam the
    /// owner heard inside a sentence never comes from packing.
    public private(set) var packLength: Int
    /// What the app's `Library` passes: see `packLength`. The initializer's own default is 0 — one
    /// sentence per utterance — so a segmenter built for a test or a tool packs nothing unless asked.
    public static let appPackLength = 160
    public var normalizer: TextNormalizer

    public init(normalizer: TextNormalizer, maxUtteranceLength: Int = 300, packLength: Int = 0) {
        precondition(maxUtteranceLength >= 2, "maxUtteranceLength must be at least 2")
        precondition(packLength >= 0, "packLength must not be negative")
        self.normalizer = normalizer
        self.maxUtteranceLength = maxUtteranceLength
        self.packLength = packLength
    }

    public func segment(_ block: SourceBlock) -> [Utterance] {
        var pieces: [(text: String, offset: Int)] = []
        for (text, offset) in sentences(in: block.text) {
            pieces += split(text, at: offset)
        }
        var result: [Utterance] = []
        for (source, offset) in packed(pieces, in: block.text) {
            let normalized = normalizer.normalize(source)
            guard !normalized.spoken.isEmpty else { continue }
            var position = block.position
            position.charOffset = block.position.charOffset.map { $0 + offset }
            result.append(Utterance(
                position: position,
                source: source,
                spoken: normalized.spoken,
                spans: normalized.spans,
                duration: .estimated(DurationEstimator.estimate(spoken: normalized.spoken))
            ))
        }
        return result
    }

    /// Joins consecutive pieces into utterances no longer than `packLength` (UTF-16 units of the
    /// block, first piece's start to last piece's end, the original text between them included). A
    /// piece longer than `packLength` on its own is its own utterance. Offsets are UTF-16 into the block.
    private func packed(_ pieces: [(text: String, offset: Int)], in text: String) -> [(String, Int)] {
        let ns = text as NSString
        var result: [(String, Int)] = []
        var start: Int?
        var end = 0
        func flush() {
            if let s = start { result.append((ns.substring(with: NSRange(location: s, length: end - s)), s)) }
            start = nil
        }
        for piece in pieces {
            let pieceEnd = piece.offset + (piece.text as NSString).length
            if let s = start, pieceEnd - s <= packLength {
                end = pieceEnd
            } else {
                flush()
                start = piece.offset
                end = pieceEnd
            }
        }
        flush()
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

    /// Splits `sentence` into pieces ≤ maxUtteranceLength by `ClauseSplitter`'s rule. Offsets are
    /// UTF-16 into the block. A sentence that fits is returned as it came, untouched.
    private func split(_ sentence: String, at offset: Int) -> [(String, Int)] {
        let ns = sentence as NSString
        guard ns.length > maxUtteranceLength else { return [(sentence, offset)] }
        return ClauseSplitter.cuts(in: sentence, maxLength: maxUtteranceLength).compactMap { range in
            Self.trimmed(ns.substring(with: range), at: offset + range.location)
        }
    }
}
