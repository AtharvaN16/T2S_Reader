import Foundation
import Testing
@testable import T2SCore

/// `PositionResolver` is the only route between a runtime `Playhead` (an utterance index) and a
/// persisted `Position` (an href plus offsets), and bookmarks, resume positions and the sync offer
/// all cross it. If the two directions disagree the app silently lands somewhere other than where
/// it saved.
@Suite struct PositionRoundTripTests {
    /// Utterances laid out the way `Segmenter` lays them out: each one's `charOffset` is its own
    /// UTF-16 offset within its resource (`Segmenter.swift:43`), so no two in a resource share a
    /// start. The fixture helper defaults `charOffset` to 0 for every utterance, which no real
    /// document does — a timeline built that way cannot round-trip and would test nothing.
    private func realisticTimeline() -> Timeline {
        func chapter(_ texts: [String], href: String) -> [Utterance] {
            var offset = 0
            return texts.map { text in
                let utterance = makeUtterance(text, href: href, charOffset: offset)
                offset += text.utf16.count + 1                  // the whitespace the segmenter trims
                return utterance
            }
        }
        return makeTimeline([
            chapter(["First sentence.", "Second one is longer than the first."], href: "ch1.xhtml"),
            chapter(["Chapter two opens here.", "And closes here."], href: "ch2.xhtml"),
            chapter(["A third chapter with one line."], href: "ch3.xhtml"),
        ])
    }

    @Test func everyUtteranceSurvivesPositionThenResolve() throws {
        let timeline = realisticTimeline()
        for index in 0..<timeline.utteranceCount {
            let playhead = Playhead(utteranceIndex: index)
            let position = PositionResolver.position(for: playhead, in: timeline)
            let back = PositionResolver.resolve(position, in: timeline)
            #expect(back.utteranceIndex == index, "utterance \(index) round-tripped to \(back.utteranceIndex)")
        }
    }

    /// The round-trip's documented limit. Two utterances claiming the same `charOffset` in one
    /// resource are indistinguishable by `Position` alone, and `resolve` returns the earlier —
    /// the fallback of spec §1.4, "never fails". The segmenter never produces this, so it is
    /// pinned here as a decision on record rather than left to be rediscovered as a bug.
    @Test func utterancesSharingACharOffsetCollapseToTheFirst() throws {
        let timeline = makeTimeline([[makeUtterance("First."), makeUtterance("Second.")]])
        let position = PositionResolver.position(for: Playhead(utteranceIndex: 1), in: timeline)
        #expect(PositionResolver.resolve(position, in: timeline).utteranceIndex == 0)
    }

    /// The `offset` half of the round trip. Every assertion above leaves `Playhead.offset` at its
    /// default of 0, where `time(atSourceOffset: 0)` and `sourceOffset(atTime: 0)` both return 0
    /// whatever the seconds-to-character maths does — so a bug in the conversion that lands a
    /// resume on the wrong word would pass unnoticed.
    ///
    /// The round trip is deliberately **not** asserted as the identity on `offset`. A `Position`
    /// stores a character, so a time is quantised to a character boundary on the way out and comes
    /// back as that character's time. The invariant that matters is idempotence: a saved position
    /// re-resolves to the same character and re-saves to the same `Position`, which is what makes a
    /// resume re-highlight the word it was saved on (`PositionResolver.swift:20-22`).
    @Test func offsetsWithinAnUtteranceSurviveTheRoundTripAsCharacters() throws {
        let timeline = realisticTimeline()
        let index = 1                                  // "Second one is longer than the first."
        let seconds = timeline[utterance: index].duration.seconds
        for fraction in [0.25, 0.5, 0.75] {
            let playhead = Playhead(utteranceIndex: index, offset: seconds * fraction)
            let position = PositionResolver.position(for: playhead, in: timeline)
            let back = PositionResolver.resolve(position, in: timeline)
            #expect(back.utteranceIndex == index, "offset at \(fraction) left the utterance")
            #expect(PositionResolver.position(for: back, in: timeline) == position,
                    "offset at \(fraction) did not re-save to the same position")
        }
    }

    /// Proof the offset is not simply discarded: three different times inside one utterance must
    /// store three different characters. Without this, the idempotence above would hold just as
    /// well for a `position(for:)` that threw the offset away entirely.
    @Test func differentOffsetsInOneUtteranceStoreDifferentCharacters() throws {
        let timeline = realisticTimeline()
        let index = 1
        let seconds = timeline[utterance: index].duration.seconds
        let stored = [0.0, 0.5, 0.9].map { fraction in
            PositionResolver.position(for: Playhead(utteranceIndex: index, offset: seconds * fraction),
                                      in: timeline).charOffset
        }
        #expect(Set(stored).count == stored.count,
                "the playhead's offset is not reaching the stored position: \(stored)")
    }
}
