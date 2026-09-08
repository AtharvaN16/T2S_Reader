import Foundation
import KokoroPipeline

/// The silence across the seam between two pieces of one utterance, cut down to what the model puts
/// at that kind of boundary inside a single call.
///
/// Every Core ML call ends with the model's end-of-input pause and begins with the BOS token's
/// lead-in, so a seam measured 400–820 ms of silence whatever the cut — inside a call the model puts
/// 25–75 ms between two words, 320–420 ms at a comma and 230–740 ms at a full stop
/// (`spikes/findings/2026-09-08-ticks-and-hyphens.md`). The head is trimmed first, because the
/// lead-in is pure silence; then the tail, which is silence too — the model's, rendered inside the
/// last word's own frames when the cut made that word utterance-final — and the timing fold clamps
/// that word's end to the trimmed audio (`KokoroCoreMLTimingFold.Piece.trimmedTailSeconds`).
enum KokoroCoreMLSeam {
    /// How the piece before a seam was closed.
    enum Cut: Sendable, Hashable {
        /// The first piece of an utterance: no seam before it.
        case none
        /// At a bare word, because no punctuation fell in the window before the cap.
        case word
        /// After a comma, semicolon, colon or dash.
        case clause
        /// After a full stop, exclamation or question mark, or an ellipsis.
        case sentence
    }

    /// Below this magnitude a sample is silence: −50 dBFS, the level every pause in the findings is
    /// measured at. The model's decays below it — the tail of a word before a cut, the ramp into the
    /// first word after it — are inaudible and are part of the hole the reader hears.
    static let silence: Float = 0.00316

    /// The silence allowed across a seam, by the cut that made it.
    static func budgetSamples(for cut: Cut) -> Int {
        let rate = PipelineConstants.sampleRate
        switch cut {
        case .none: return .max
        case .word: return rate * 60 / 1000
        case .clause: return rate * 320 / 1000
        case .sentence: return rate * 500 / 1000
        }
    }

    /// The tail of a piece that is emitted before its successor exists (a streamed head, Plan 14):
    /// its trailing silence cut to at most `budget` samples. Never emptied, never touched when the
    /// piece is silence throughout.
    static func trimmedTail(_ audio: [Float], budget: Int) -> (audio: [Float], dropped: Int) {
        guard budget < .max else { return (audio, 0) }
        var tail = 0
        while tail < audio.count, abs(audio[audio.count - 1 - tail]) < silence { tail += 1 }
        guard tail < audio.count, tail > budget else { return (audio, 0) }
        let dropped = tail - budget
        return (Array(audio.dropLast(dropped)), dropped)
    }

    /// The head of a piece that follows one already emitted: its lead-in silence cut, at most `cap`
    /// samples (the BOS token's own frames — the fold counts from there). Never emptied.
    static func trimmedHead(_ audio: [Float], cap: Int) -> (audio: [Float], dropped: Int) {
        var head = 0
        while head < audio.count, abs(audio[head]) < silence { head += 1 }
        guard head < audio.count else { return (audio, 0) }
        let dropped = min(head, max(0, cap))
        return (Array(audio.dropFirst(dropped)), dropped)
    }

    /// `previous` and `next` with the silence across their join cut to at most `budget` samples —
    /// from the head of `next` first (at most `headCap`), then from the tail of `previous` (at most
    /// `tailCap`) — and how much each side lost. Neither side is ever emptied.
    static func trimmed(
        previous: [Float], next: [Float], budget: Int, tailCap: Int, headCap: Int
    ) -> (previous: [Float], next: [Float], droppedTail: Int, droppedHead: Int) {
        var head = 0
        while head < next.count, abs(next[head]) < silence { head += 1 }
        var tail = 0
        while tail < previous.count, abs(previous[previous.count - 1 - tail]) < silence { tail += 1 }
        guard head < next.count, tail < previous.count, budget < .max else { return (previous, next, 0, 0) }
        var excess = head + tail - budget
        guard excess > 0 else { return (previous, next, 0, 0) }
        let droppedHead = min(excess, head, max(0, headCap))
        excess -= droppedHead
        let droppedTail = min(excess, tail, max(0, tailCap))
        return (Array(previous.dropLast(droppedTail)), Array(next.dropFirst(droppedHead)), droppedTail, droppedHead)
    }
}
