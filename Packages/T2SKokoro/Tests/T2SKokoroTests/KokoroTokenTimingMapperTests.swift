import Foundation
import Testing
import T2SCore
@testable import T2SKokoro

@Suite struct KokoroTokenTimingMapperTests {
    /// "Hello world", spoken exactly as the engine received it, with plausible Misaki timestamps.
    static let hello = KokoroToken(text: "Hello", whitespace: " ", start: 0.0, end: 0.4)
    static let world = KokoroToken(text: "world", whitespace: "", start: 0.5, end: 0.9)
    static let spoken = "Hello world"

    /// The §7.4 gate is open (2026-09-04): `map` now hands the highlighter the candidate timings.
    @Test func mapReturnsTheCandidateTimingsNowTheGateIsOpen() {
        #expect(KokoroTokenTimingMapper.map([Self.hello, Self.world], spoken: Self.spoken, duration: 1.0) == [
            WordTiming(spokenRange: 0..<5, start: 0.0, end: 0.4),
            WordTiming(spokenRange: 6..<11, start: 0.5, end: 0.9),
        ])
    }

    /// Opening the gate did not soften it: a token stream that has drifted apart from the text is
    /// still dropped whole rather than half-highlighted.
    @Test func mapIsStillEmptyWhenATokenIsNotInTheSpokenText() {
        let stray = KokoroToken(text: "moon", whitespace: "", start: 0.5, end: 0.9)
        #expect(KokoroTokenTimingMapper.map([Self.hello, stray], spoken: Self.spoken, duration: 1.0).isEmpty)
    }

    @Test func candidateTimingsLocateEachTokenInTheSpokenText() {
        let timings = KokoroTokenTimingMapper.candidateTimings([Self.hello, Self.world], spoken: Self.spoken, duration: 1.0)
        #expect(timings == [
            WordTiming(spokenRange: 0..<5, start: 0.0, end: 0.4),
            WordTiming(spokenRange: 6..<11, start: 0.5, end: 0.9),
        ])
    }

    @Test func candidateTimingsClampToTheAudioDuration() {
        let overrun = KokoroToken(text: "world", whitespace: "", start: 0.5, end: 1.4)
        let timings = KokoroTokenTimingMapper.candidateTimings([Self.hello, overrun], spoken: Self.spoken, duration: 1.0)
        #expect(timings.last == WordTiming(spokenRange: 6..<11, start: 0.5, end: 1.0))
    }

    @Test func candidateTimingsRefuseATokenThatIsNotInTheSpokenText() {
        let stray = KokoroToken(text: "moon", whitespace: "", start: 0.5, end: 0.9)
        #expect(KokoroTokenTimingMapper.candidateTimings([Self.hello, stray], spoken: Self.spoken, duration: 1.0).isEmpty)
    }

    @Test func candidateTimingsSkipATokenThatEndsBeforeItStarts() {
        let inverted = KokoroToken(text: "moon", whitespace: " ", start: 0.9, end: 0.2)
        let timings = KokoroTokenTimingMapper.candidateTimings([Self.hello, inverted, Self.world],
                                                              spoken: Self.spoken, duration: 1.0)
        #expect(timings == [
            WordTiming(spokenRange: 0..<5, start: 0.0, end: 0.4),
            WordTiming(spokenRange: 6..<11, start: 0.5, end: 0.9),
        ])
    }

    @Test func candidateTimingsSkipATokenThatGoesBackwardsAgainstTheOneBefore() {
        let backwards = KokoroToken(text: "world", whitespace: "", start: 0.1, end: 0.2)
        let timings = KokoroTokenTimingMapper.candidateTimings([Self.world, backwards], spoken: Self.spoken, duration: 1.0)
        #expect(timings == [WordTiming(spokenRange: 6..<11, start: 0.5, end: 0.9)])
    }

    @Test func candidateTimingsSkipTokensWithoutUsableTimestamps() {
        let untimed = KokoroToken(text: "moon", whitespace: " ", start: nil, end: 0.3)
        let infinite = KokoroToken(text: "moon", whitespace: " ", start: 0.1, end: .infinity)
        let blank = KokoroToken(text: " ", whitespace: "", start: 0.45, end: 0.45)
        let timings = KokoroTokenTimingMapper.candidateTimings([Self.hello, untimed, infinite, blank, Self.world],
                                                              spoken: Self.spoken, duration: 1.0)
        #expect(timings == [
            WordTiming(spokenRange: 0..<5, start: 0.0, end: 0.4),
            WordTiming(spokenRange: 6..<11, start: 0.5, end: 0.9),
        ])
    }

    @Test func candidateTimingsAreEmptyForNoTokens() {
        #expect(KokoroTokenTimingMapper.candidateTimings([], spoken: Self.spoken, duration: 1.0).isEmpty)
    }
}
