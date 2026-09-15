import Foundation
import Testing
@testable import T2SApp

@Suite struct RisingChoreographyTests {
    let scene = RisingChoreography(count: 5, stride: 2, travel: 5)

    @Test func cardsEnterOneStrideApart() {
        #expect(scene.start(of: 0) == 0)
        #expect(scene.start(of: 3) == 6)
        #expect(scene.heroIndex == 4)
    }

    @Test func progressRunsFromEntryToExitOverTheTravel() {
        #expect(scene.progress(of: 1, at: 2) == 0)
        #expect(scene.progress(of: 1, at: 4.5) == 0.5)
        #expect(scene.progress(of: 1, at: 7) == 1)
        #expect(scene.progress(of: 1, at: 1) < 0)
    }

    /// A voice is silent below the screen, full through the middle of the climb, and gone before
    /// the top — a long line is cut, not finished.
    @Test func aVoiceFollowsItsCard() {
        #expect(scene.gain(of: 0, at: -1) == 0)
        #expect(scene.gain(of: 0, at: 0) == 0)
        #expect(abs(scene.gain(of: 0, at: 2.5) - RisingChoreography.baseGains[0]) < 0.001)   // mid-climb, base gain
        #expect(scene.gain(of: 0, at: 4.4) > 0)                                             // fading
        #expect(scene.gain(of: 0, at: 4.4) < RisingChoreography.baseGains[0])
        #expect(scene.gain(of: 0, at: 4.7) == 0)                                            // gone before the top
    }

    /// Two voices at once: while the second is mid-climb the first is still up.
    @Test func voicesOverlap() {
        let t = scene.start(of: 1) + 1
        #expect(scene.gain(of: 0, at: t) > 0)
        #expect(scene.gain(of: 1, at: t) > 0)
    }

    @Test func voicesHaveDifferentVolumes() {
        let mid = { (i: Int) in self.scene.gain(of: i, at: self.scene.start(of: i) + 2.5) }
        #expect(mid(0) != mid(1))
        #expect(mid(2) == 1)
    }

    /// The hero says nothing on the way up — its lines wait for Play — and the scene ends a
    /// breath after it lands.
    @Test func theHeroIsSilentAndEndsTheScene() {
        let hero = scene.heroIndex
        #expect(scene.gain(of: hero, at: scene.start(of: hero) + 2.5) == 0)
        #expect(scene.settled == scene.start(of: hero) + 5)
        #expect(scene.total == scene.settled + 0.3)
        #expect(scene.settleStart < scene.settled)
    }

    @Test func gainsCoverEveryCard() {
        #expect(scene.gains(at: 3).count == 5)
    }

    @Test func oneCardIsTheHeroAlone() {
        let solo = RisingChoreography(count: 1, stride: 2, travel: 5)
        #expect(solo.heroIndex == 0)
        #expect(solo.gains(at: 2) == [0])
    }
}
