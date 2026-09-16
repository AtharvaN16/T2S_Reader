import Foundation
import Testing
@testable import T2SApp

@Suite struct SleepCardReadingTests {
    @Test func aTimedSleepHandsOverItsDeadlineToTickOnItsOwn() throws {
        let deadline = Date(timeIntervalSince1970: 1_000_000)
        let reading = try #require(SleepCardReading.make(option: .minutes(30), deadline: deadline,
                                                         chapterTitle: nil))
        #expect(reading.headline == "Sleep timer")
        #expect(reading.deadline == deadline)
        #expect(reading.detail == "Playback stops when the time is up")
    }

    /// No deadline exists for this one, so the card must not pretend to count anything down.
    @Test func endOfChapterNamesTheChapterAndHasNoClock() throws {
        let reading = try #require(SleepCardReading.make(option: .endOfChapter, deadline: nil,
                                                         chapterTitle: "The Siege of Delhi"))
        #expect(reading.headline == "Sleep timer")
        #expect(reading.detail == "Until the end of The Siege of Delhi")
        #expect(reading.deadline == nil)
    }

    @Test func noTimerMeansNoCard() {
        #expect(SleepCardReading.make(option: nil, deadline: nil, chapterTitle: nil) == nil)
    }

    /// A timed option with no deadline is a contradiction — it must not produce a card that
    /// silently never ends.
    @Test func aTimedOptionWithoutADeadlineIsNoCard() {
        #expect(SleepCardReading.make(option: .minutes(30), deadline: nil, chapterTitle: nil) == nil)
    }
}
