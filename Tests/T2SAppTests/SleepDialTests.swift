import Foundation
import Testing
@testable import T2SApp

/// The sleep sheet's ruler: where the finger can land, and where it is drawn to.
@Suite struct SleepDialTests {
    @Test func stopsRunFromFiveMinutesToTwoHoursInFives() {
        #expect(SleepDial.stops.first == 5 && SleepDial.stops.last == 120)
        #expect(SleepDial.stops.count == 24)
        #expect(SleepDial.stops.allSatisfy { $0 % SleepDial.step == 0 })
        #expect(SleepDial.stops == SleepDial.stops.sorted())
    }

    /// The old chips are still on the bar, taller and named, and every one of them is a stop the
    /// finger can actually rest on.
    @Test func landmarksAreTheOldChipsAndTheTwoHours() {
        #expect(SleepDial.landmarks == [10, 20, 30, 45, 60, 90, 120])
        #expect(SleepDial.landmarks.allSatisfy { SleepDial.stops.contains($0) })
        #expect(SleepDial.stops.contains(SleepDial.defaultMinutes))
    }

    @Test func snappingLandsOnTheNearestStopInsideTheRange() {
        #expect(SleepDial.snapped(0) == 5)
        #expect(SleepDial.snapped(-30) == 5)
        #expect(SleepDial.snapped(200) == 120)
        #expect(SleepDial.snapped(32) == 30)
        #expect(SleepDial.snapped(33) == 35)
        #expect(SleepDial.snapped(45) == 45)
        #expect(SleepDial.snapped(7) == 5 && SleepDial.snapped(8) == 10)
    }

    @Test func aFingerAcrossTheBarVisitsEveryStopOnce() {
        #expect(SleepDial.minutes(atFraction: 0) == 5)
        #expect(SleepDial.minutes(atFraction: 1) == 120)
        #expect(SleepDial.minutes(atFraction: -0.5) == 5)
        #expect(SleepDial.minutes(atFraction: 1.5) == 120)
        #expect(SleepDial.minutes(atFraction: 0.5) == 65)
        for stop in SleepDial.stops {
            #expect(SleepDial.minutes(atFraction: SleepDial.fraction(of: stop)) == stop)
        }
        #expect(SleepDial.fraction(of: 5) == 0 && SleepDial.fraction(of: 120) == 1)
        #expect(SleepDial.fraction(of: 7) == SleepDial.fraction(of: 5))          // off-stop values snap first
    }
}
