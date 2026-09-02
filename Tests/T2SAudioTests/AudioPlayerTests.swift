import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@MainActor
@Suite struct AudioPlayerTests {
    @Test func consumedSecondsTracksAudioTimeAtOneX() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.enqueue(.silence(seconds: 2), tag: 1)
        p.play()
        try p.renderOffline(seconds: 0.5)
        #expect(abs(p.consumedSeconds - 0.5) < 0.05)
        try p.renderOffline(seconds: 1.0)
        #expect(abs(p.consumedSeconds - 1.5) < 0.05)
    }

    @Test func rateTwoConsumesTwiceAsFast() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.rate = 2.0
        p.enqueue(.silence(seconds: 4), tag: 1)
        p.play()
        try p.renderOffline(seconds: 1.0)
        #expect(abs(p.consumedSeconds - 2.0) < 0.15)               // time-pitch buffers a little
    }

    @Test func segmentsFinishInOrderAndGaplessly() throws {
        let p = try AudioPlayer(manualRendering: true)
        var finished: [Int] = []
        p.onSegmentFinished = { finished.append($0) }
        p.enqueue(.silence(seconds: 0.5), tag: 10)
        p.enqueue(.silence(seconds: 0.5), tag: 11)
        p.play()
        try p.renderOffline(seconds: 0.6)
        #expect(finished == [10])
        try p.renderOffline(seconds: 0.6)
        #expect(finished == [10, 11])
        #expect(abs(p.consumedSeconds - 1.0) < 0.05)               // stops consuming when the queue drains
    }

    @Test func resetClearsQueueAndClock() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.enqueue(.silence(seconds: 2), tag: 1)
        p.play()
        try p.renderOffline(seconds: 1.0)
        p.reset()
        #expect(p.consumedSeconds == 0)
        #expect(!p.isPlaying)
        p.enqueue(.silence(seconds: 1), tag: 2)
        p.play()
        try p.renderOffline(seconds: 0.25)
        #expect(abs(p.consumedSeconds - 0.25) < 0.05)
    }

    @Test func rateIsClampedToSpecRange() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.rate = 9
        #expect(p.rate == 4)
        p.rate = 0.1
        #expect(p.rate == 0.5)
    }

    @Test func rateChangeMidStreamIntegrates() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.enqueue(.silence(seconds: 6), tag: 1)
        p.play()
        try p.renderOffline(seconds: 1.0)                          // 1.0 s of source at 1x
        #expect(abs(p.consumedSeconds - 1.0) < 0.05)
        p.rate = 2.0
        try p.renderOffline(seconds: 1.0)                          // 2.0 s more of source at 2x
        #expect(abs(p.consumedSeconds - 3.0) < 0.15)
    }
}
