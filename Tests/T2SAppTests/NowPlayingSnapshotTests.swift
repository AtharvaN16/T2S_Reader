import Foundation
import Testing
@testable import T2SApp

@Suite struct NowPlayingSnapshotTests {
    @Test func pausedSnapshotStopsClockAndUsesOneBasedChapter() {
        let value = NowPlayingSnapshot(title: "The Book", author: "Ada", duration: 600,
                                       elapsed: 42, rate: 2, isPlaying: false,
                                       chapterIndex: 1, chapterCount: 12, queueIndex: 0, queueCount: 3)
        #expect(value.playbackRate == 0)
        #expect(value.defaultPlaybackRate == 2)
        #expect(value.chapterNumber == 2 && value.queueIndex == 0 && value.queueCount == 3)
    }

    @Test func remoteRateOnlyAcceptsAdvertisedRatesAndSeekIsClamped() {
        #expect(NowPlayingSnapshot.acceptedRate(2, available: [0.5, 1, 1.5, 2]) == 2)
        #expect(NowPlayingSnapshot.acceptedRate(3, available: [0.5, 1, 1.5, 2]) == nil)
        #expect(NowPlayingSnapshot.clampedSeek(700, duration: 600) == 600)
        #expect(NowPlayingSnapshot.clampedSeek(-3, duration: 600) == 0)
    }
}
