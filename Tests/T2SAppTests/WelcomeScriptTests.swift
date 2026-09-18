import Foundation
import Testing
@testable import T2SApp

@Suite struct WelcomeScriptTests {
    let script = WelcomeScript(reelEnd: 10, rise: 1, hold: 2)

    @Test func theThreeBeatsFollowOneAnother() {
        #expect(script.beat(at: 0) == .reel)
        #expect(script.beat(at: 9.9) == .reel)
        // The beat turns the moment the veil starts, since what it uncovers is what the scene is
        // now about — even while most of the screen still shows the reel.
        #expect(script.beat(at: 10) == .welcome)
        #expect(script.beat(at: 12.9) == .welcome)
        #expect(script.beat(at: 13) == .page)
        #expect(script.beat(at: 100) == .page)
    }

    @Test func theNameHoldsAloneBetweenTheTwoRises() {
        #expect(script.welcomeStart == 10)
        #expect(script.pageStart == 13)          // reelEnd + rise + hold
        #expect(script.pageSettled == 14)        // and one more rise to be uncovered
    }

    /// Both veils are the one overlay travelling: bottom of the screen to the crown, eased at each
    /// end, and clamped outside their own beat.
    @Test func eachVeilTravelsTheHeightOfTheScreenOnce() {
        #expect(script.welcomeSweep(at: 9) == 0)
        #expect(script.welcomeSweep(at: 10) == 0)
        #expect(abs(script.welcomeSweep(at: 10.5) - 0.5) < 0.0001)
        #expect(script.welcomeSweep(at: 11) == 1)
        #expect(script.welcomeSweep(at: 30) == 1)

        #expect(script.pageSweep(at: 12) == 0)
        #expect(abs(script.pageSweep(at: 13.5) - 0.5) < 0.0001)
        #expect(script.pageSweep(at: 14) == 1)
    }

    /// The first veil is home well before the second sets off, so the name is never uncovered and
    /// covered at once.
    @Test func theVeilsDoNotOverlap() {
        #expect(script.welcomeSweep(at: script.pageStart) == 1)
    }

    @Test func theRampEasesRatherThanSnapping() {
        #expect(WelcomeScript.ramp(-1) == 0)
        #expect(WelcomeScript.ramp(2) == 1)
        // Slow off the mark: a sheet drawn up, not a shutter dropped.
        #expect(WelcomeScript.ramp(0.1) < 0.1)
        #expect(WelcomeScript.ramp(0.9) > 0.9)
    }

    /// The greeting rides the veil; the name arrives after it, and is fully in well before the
    /// hold is over — otherwise the second veil would take it away mid-word.
    @Test func theNameArrivesAfterTheVeilAndBeforeTheHoldIsOver() {
        let script = WelcomeScript(reelEnd: 10, rise: 1, hold: 2)
        #expect(script.nameIn(at: 11) == 0)                      // veil just home, name not yet
        #expect(script.nameIn(at: 11 + script.nameDelay) == 0)   // and not until its delay is up
        #expect(script.nameIn(at: 11 + script.nameDelay + script.nameFade) == 1)
        #expect(script.nameIn(at: script.pageStart) == 1)        // whole before the page rises
    }

    @Test func theReelIsShortAndOwnsItsOwnLength() {
        #expect(WelcomeScript().reelEnd == WelcomeScript.defaultReel)
        #expect(WelcomeScript.defaultReel < 8)
    }
}
