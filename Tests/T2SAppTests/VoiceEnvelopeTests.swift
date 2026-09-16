import Foundation
import Testing
@testable import T2SApp

@Suite struct VoiceEnvelopeTests {
    // Two words with a gap between them, and a long one after it.
    let envelope = VoiceEnvelope(words: [(0.0, 0.3), (0.5, 0.8), (1.5, 3.5)])
    let floor = VoiceEnvelope.floor

    @Test func silenceSitsAtTheFloorRatherThanGoingDark() {
        #expect(envelope.level(at: -1) == floor)          // before the first word
        #expect(envelope.level(at: 0.4) == floor)          // in the gap
        #expect(envelope.level(at: 10) == floor)           // after the last
    }

    @Test func aWordAttacksToFullThenFallsAway() {
        #expect(envelope.level(at: 0) == floor)
        #expect(abs(envelope.level(at: VoiceEnvelope.attack) - 1) < 0.0001)
        let mid = envelope.level(at: 0.15)
        #expect(mid < 1)
        #expect(mid > floor)
        #expect(envelope.level(at: 0.29) < mid)
    }

    /// A word held for two seconds must not hold the glow up for two seconds with it: the decay is
    /// capped, so the level is back near the floor well before the word ends.
    @Test func aLongWordStillDecays() {
        #expect(abs(envelope.level(at: 1.5 + VoiceEnvelope.attack) - 1) < 0.0001)
        #expect(envelope.level(at: 1.5 + VoiceEnvelope.attack + VoiceEnvelope.decay) == floor)
        #expect(envelope.level(at: 3.0) == floor)
    }

    @Test func theLevelNeverLeavesItsRange() {
        for step in 0 ... 400 {
            let level = envelope.level(at: Double(step) / 100)
            #expect(level >= floor)
            #expect(level <= 1)
        }
    }

    @Test func noTimingsMeansAStillGlowRatherThanACrash() {
        let none = VoiceEnvelope(timings: nil)
        #expect(none.level(at: 0) == floor)
        #expect(none.level(at: 5) == floor)
    }

    @Test func itReadsTheWordTimingsTheReadAlongUses() {
        let timings = OnboardingClipTimings(
            book: "alices-adventures-in-wonderland", voice: "af_heart", spoken: "Alice was",
            duration: 1, words: [.init(start: 0.1, end: 0.4, range: [0, 5]),
                                 .init(start: 0.45, end: 0.7, range: [6, 9])])
        let envelope = VoiceEnvelope(timings: timings)
        #expect(envelope.level(at: 0.05) == floor)
        #expect(abs(envelope.level(at: 0.1 + VoiceEnvelope.attack) - 1) < 0.0001)
    }
}
