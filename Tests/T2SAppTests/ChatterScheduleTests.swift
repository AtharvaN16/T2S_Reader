import Foundation
import Testing
@testable import T2SApp

@Suite struct ChatterScheduleTests {
    // Three lines: 2 s, 8 s, 3 s; fade in over 0.5 s, cross over 1 s.
    let schedule = ChatterSchedule(durations: [2, 8, 3], fadeIn: 0.5, crossfade: 1)
    let lead = ChatterSchedule.lead

    @Test func linesFollowOneAnotherWithTheCrossfadeOverlapping() {
        #expect(schedule.start(of: 0) == lead)
        #expect(schedule.end(of: 0) == lead + 2)
        #expect(schedule.start(of: 1) == lead + 2 - 1)        // starts as the first tails off
        #expect(schedule.start(of: 2) == lead + 2 - 1 + 8 - 1)
    }

    /// Each line plays whole: full through its middle, down only over its last second.
    @Test func aLineIsHeardToItsEnd() {
        let s = schedule.start(of: 1), e = schedule.end(of: 1)
        #expect(schedule.gain(of: 1, at: s - 0.1) == 0)
        #expect(abs(schedule.gain(of: 1, at: s + 0.25) - 0.5 * ChatterSchedule.baseGains[1]) < 0.001)   // rising
        #expect(abs(schedule.gain(of: 1, at: s + 4) - ChatterSchedule.baseGains[1]) < 0.001)             // held
        #expect(abs(schedule.gain(of: 1, at: e - 0.5) - 0.5 * ChatterSchedule.baseGains[1]) < 0.001)     // falling
        #expect(schedule.gain(of: 1, at: e) == 0)
    }

    /// While one line falls the next rises: both are audible.
    @Test func voicesHandOver() {
        let t = schedule.start(of: 1) + 0.4
        #expect(schedule.gain(of: 0, at: t) > 0)
        #expect(schedule.gain(of: 1, at: t) > 0)
    }

    @Test func voicesHaveDifferentVolumes() {
        let held = { (i: Int) in self.schedule.gain(of: i, at: self.schedule.start(of: i) + 1.2) }
        #expect(held(0) != held(1))
        #expect(held(2) == 1)
    }

    /// A very short line still gets its half second before the next starts.
    @Test func aShortLineIsNotSwallowed() {
        let quick = ChatterSchedule(durations: [0.3, 4], fadeIn: 0.5, crossfade: 1)
        #expect(quick.start(of: 1) == lead + 0.5)
    }

    /// The reel gives way only once the last line has fully tailed off, so the app's name never
    /// lands over a voice still speaking.
    @Test func theChatterEndsWithItsLastLine() {
        #expect(schedule.chatterEnd == schedule.end(of: 2))
        #expect(schedule.gain(of: 2, at: schedule.chatterEnd) == 0)
    }

    /// A bundle with no rendered clips still runs a reel worth watching before the name.
    @Test func noChatterStillRunsAReel() {
        let silent = ChatterSchedule(durations: [])
        #expect(silent.gains(at: 1).isEmpty)
        #expect(silent.chatterEnd == ChatterSchedule.lead + ChatterSchedule.silentReel)
    }

    @Test func gainsCoverEveryLine() {
        #expect(schedule.gains(at: 3).count == 3)
    }
}
