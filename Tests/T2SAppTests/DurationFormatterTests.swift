import Foundation
import Testing
@testable import T2SApp

@Suite struct DurationFormatterTests {
    @Test func longForm() {
        #expect(DurationFormatter.long(0) == "0m")
        #expect(DurationFormatter.long(59) == "1m")                          // rounds to the nearest minute
        #expect(DurationFormatter.long(42 * 60) == "42m")
        #expect(DurationFormatter.long(6 * 3600 + 20 * 60) == "6h 20m")
        #expect(DurationFormatter.long(2 * 3600) == "2h")
        #expect(DurationFormatter.long(6 * 3600 + 20 * 60, approximate: true) == "~6h 20m")
    }

    @Test func remainingForm() {
        #expect(DurationFormatter.remaining(12 * 60 + 5, approximate: true) == "~12m")
        #expect(DurationFormatter.remaining(3600 + 5 * 60, approximate: false) == "1h 5m")
        #expect(DurationFormatter.remaining(20, approximate: false) == "<1m")
        #expect(DurationFormatter.remaining(20, approximate: true) == "<1m")
    }

    @Test func coarseRemainingForm() {
        #expect(DurationFormatter.coarseRemaining(0) == "<1 min")
        #expect(DurationFormatter.coarseRemaining(59) == "<1 min")
        #expect(DurationFormatter.coarseRemaining(-5) == "<1 min")                        // behaves as 0
        #expect(DurationFormatter.coarseRemaining(60) == "1 min")
        #expect(DurationFormatter.coarseRemaining(42 * 60 + 20) == "42 min")
        #expect(DurationFormatter.coarseRemaining(42 * 60 + 40) == "43 min")              // nearest minute
        #expect(DurationFormatter.coarseRemaining(59 * 60 + 45) == "1 hr")                // 60 min is the hour
        #expect(DurationFormatter.coarseRemaining(3600) == "1 hr")
        #expect(DurationFormatter.coarseRemaining(3600 + 20 * 60) == "1 hr")
        #expect(DurationFormatter.coarseRemaining(3600 + 40 * 60) == "2 hrs")             // nearest hour
        #expect(DurationFormatter.coarseRemaining(22 * 3600 + 20 * 60) == "22 hrs")
        #expect(DurationFormatter.coarseRemaining(22 * 3600 + 39 * 60) == "23 hrs")
    }

    @Test func clockForm() {
        #expect(DurationFormatter.clock(0) == "0:00")
        #expect(DurationFormatter.clock(42) == "0:42")
        #expect(DurationFormatter.clock(12 * 60 + 5) == "12:05")
        #expect(DurationFormatter.clock(3600 + 2 * 60 + 33) == "1:02:33")
        #expect(DurationFormatter.clock(-3) == "0:00")
    }

    @Test func ages() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func age(_ seconds: TimeInterval) -> String { DurationFormatter.age(of: now.addingTimeInterval(-seconds), now: now) }
        #expect(age(30) == "now")
        #expect(age(5 * 60) == "5m")
        #expect(age(3 * 3600) == "3h")
        #expect(age(2 * 86_400) == "2d")
        #expect(age(3 * 7 * 86_400) == "3w")
        #expect(age(120 * 86_400) == "4mo")
        #expect(age(400 * 86_400) == "1y")
        #expect(age(-60) == "now")                                           // clock skew
    }

    @Test func itemCounts() {
        #expect(DurationFormatter.items(0) == "0 items")
        #expect(DurationFormatter.items(1) == "1 item")
        #expect(DurationFormatter.items(14) == "14 items")
    }
}
