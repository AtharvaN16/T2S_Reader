import Foundation
import KokoroPipeline

/// The pure half of the Core ML engine's word timings: the pipeline's per-input-token duration
/// frames folded back onto the Misaki tokens that own them.
///
/// Split out of the engine because it is arithmetic — no model, no G2P — and because §7.4 is decided
/// here. `spikes/findings/2026-09-04-pre-a14-runtime.md` measured word onsets from this fold against
/// the audio on an A13: worst onset error 55 ms against a ±100 ms bar. Word *ends* were up to 315 ms
/// late in that run because the pause after a word was charged to the word; the fix is below, in the
/// owners this fold refuses to count.
enum KokoroCoreMLTimingFold {
    /// The owner of an input id that belongs to no word: the whitespace between two Misaki tokens.
    /// Its frames are the pause after a word, and charging them to that word is exactly the §7.4
    /// word-end error.
    static let noOwner = -1

    /// 600 samples at 24 kHz — 25 ms. Settled from the audio in §7.4 (an energy envelope over the
    /// spike's WAVs: at 12.5 ms per frame the second half of every file would be silence).
    static let secondsPerFrame =
        Double(PipelineConstants.samplesPerDurationFrame) / Double(PipelineConstants.sampleRate)

    /// One synthesized piece's alignment. A long utterance is synthesized in consecutive pieces (see
    /// ``KokoroCoreMLEngine/maxPieceTokenCount``), each with its own frame counts, and each offset by
    /// the audio the pieces before it produced.
    struct Piece: Hashable, Sendable {
        /// One entry per input id in the piece: the index of the Misaki token that contributed it, or
        /// ``noOwner``.
        var owners: [Int]
        /// `KokoroPipeline.SynthesisResult.tokenDurationFrames`, aligned with the framed input ids
        /// (`boundary + ids + boundary`) — so `owners[k]`'s frames are `frames[k + 1]`, and entry 0
        /// is the BOS boundary's lead-in.
        var frames: [Int]
        /// Seconds of audio the earlier pieces already produced.
        var offsetSeconds: Double

        init(owners: [Int], frames: [Int], offsetSeconds: Double) {
            self.owners = owners
            self.frames = frames
            self.offsetSeconds = offsetSeconds
        }
    }

    /// Times each token from the frames of the input ids it owns, in the piece that carried it.
    ///
    /// A token keeps `start`/`end` of `nil` — which the timing mapper skips — when it owns no id at
    /// all (every one of its phoneme characters was outside the vocabulary), or when it says nothing
    /// a reader could follow. Punctuation is the second case: a full stop owns the breath after the
    /// sentence, which is where the trailing pause belongs, but highlighting a full stop is not what
    /// the timings are for.
    static func timedTokens(_ tokens: [KokoroToken], pieces: [Piece]) -> [KokoroToken] {
        var spans: [Int: (start: Double, end: Double)] = [:]
        for piece in pieces {
            // A Misaki token never straddles a piece boundary — pieces are cut between tokens — so
            // no two pieces can claim the same one.
            spans.merge(self.spans(in: piece)) { existing, _ in existing }
        }

        return tokens.enumerated().map { index, token in
            guard let span = spans[index], isAWord(token.text) else { return token }
            var timed = token
            timed.start = span.start
            timed.end = span.end
            return timed
        }
    }

    /// First and last frame boundary of every token that owns an id in this piece.
    private static func spans(in piece: Piece) -> [Int: (start: Double, end: Double)] {
        // Frames before input id `k`, with the BOS entry's lead-in already spent.
        var cumulative = [Int](repeating: 0, count: piece.owners.count + 1)
        cumulative[0] = piece.frames.first ?? 0
        for k in 0 ..< piece.owners.count {
            cumulative[k + 1] = cumulative[k] + (k + 1 < piece.frames.count ? piece.frames[k + 1] : 0)
        }

        var first: [Int: Int] = [:]
        var last: [Int: Int] = [:]
        for (k, owner) in piece.owners.enumerated() where owner != noOwner {
            if first[owner] == nil { first[owner] = k }
            last[owner] = k
        }

        return first.reduce(into: [:]) { spans, entry in
            let (owner, firstID) = entry
            guard let lastID = last[owner] else { return }
            spans[owner] = (piece.offsetSeconds + Double(cumulative[firstID]) * secondsPerFrame,
                            piece.offsetSeconds + Double(cumulative[lastID + 1]) * secondsPerFrame)
        }
    }

    /// Whether a token is something the highlighter can underline, rather than the punctuation
    /// between two of them.
    private static func isAWord(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }
}
