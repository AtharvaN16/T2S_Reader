import Foundation
import T2SCore

/// One Misaki token as the engine saw it; decoupled from the `MToken` class so the mapper is
/// testable without a model, and so nothing non-`Sendable` leaves the engine actor.
public struct KokoroToken: Hashable, Sendable {
    /// The token's text, which the engine received as a substring of `SynthesisRequest.spoken`.
    public var text: String
    /// The whitespace that followed the token in that text.
    public var whitespace: String
    /// Seconds from the start of the utterance, when the runtime predicted them.
    public var start: Double?
    public var end: Double?

    public init(text: String, whitespace: String, start: Double?, end: Double?) {
        self.text = text
        self.whitespace = whitespace
        self.start = start
        self.end = end
    }
}

/// Turns Misaki's per-token timestamps into the `WordTiming`s the highlighter reads.
public enum KokoroTokenTimingMapper {
    /// Spec §7.4 gate: word timings from this runtime are unproven until the 17 Pro fixture exists
    /// (plan adjustment 5 — the `timing` rows of the 17 Pro spike CSV, which nobody has captured
    /// yet). Returns `[]` so the highlighter falls back to the estimated timeline rather than
    /// highlighting the wrong words with total confidence. When the fixture lands and pins
    /// ``candidateTimings(_:spoken:duration:)`` against real audio, this forwards to it.
    public static func map(_ tokens: [KokoroToken], spoken: String, duration: TimeInterval) -> [WordTiming] {
        []
    }

    /// The mapping ``map(_:spoken:duration:)`` will return once the fixture proves it. Internal on
    /// purpose: until then it is only ever exercised on synthetic arithmetic.
    ///
    /// Tokens are walked in order and one is used only when it can be trusted: non-blank text, both
    /// timestamps present and finite, `start <= end`, and neither timestamp earlier than the last
    /// used token's. Each token's text is then located in `spoken` — searching forward from the end
    /// of the previous match, since the engine is handed exactly `spoken` and the tokens come out in
    /// reading order. A token that cannot be located means the token stream and the text have
    /// drifted apart, and the whole utterance is dropped rather than half-highlighted.
    static func candidateTimings(_ tokens: [KokoroToken], spoken: String, duration: TimeInterval) -> [WordTiming] {
        var timings: [WordTiming] = []
        var searchFrom = spoken.startIndex
        var previous: (start: Double, end: Double)?

        for token in tokens {
            guard !token.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let start = token.start, let end = token.end,
                  start.isFinite, end.isFinite, start <= end,
                  previous.map({ start >= $0.start && end >= $0.end }) ?? true
            else { continue }
            guard let found = spoken.range(of: token.text, range: searchFrom ..< spoken.endIndex) else { return [] }

            // Clamping `start` too keeps `start <= end` when a token overruns the audio entirely.
            let clampedEnd = min(end, duration)
            let utf16Range = NSRange(found, in: spoken)
            timings.append(WordTiming(spokenRange: utf16Range.lowerBound ..< utf16Range.upperBound,
                                      start: min(start, clampedEnd),
                                      end: clampedEnd))
            previous = (start, end)
            searchFrom = found.upperBound
        }
        return timings
    }
}
