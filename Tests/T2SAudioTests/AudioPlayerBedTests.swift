import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@MainActor
@Suite struct AudioPlayerBedTests {
    /// One second of a 220 Hz tone at 48 kHz, which is what a decoded loop looks like.
    private func tone() -> PCMAudio {
        PCMAudio(sampleRate: 48_000, samples: (0..<48_000).map { Float(sin(Double($0) * 2 * .pi * 220 / 48_000)) * 0.5 })
    }

    @Test func theBedIsHeardAtVolumeAndSilentAtZero() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.setBed(tone())
        p.setBedVolume(0)
        try p.renderOffline(seconds: 0.2)
        #expect(p.lastRenderPeak == 0)
        p.setBedVolume(0.5)
        try p.renderOffline(seconds: 0.2)
        #expect(p.lastRenderPeak > 0.1)
        p.setBed(nil)
        try p.renderOffline(seconds: 0.2)
        #expect(p.lastRenderPeak == 0)
    }

    @Test func theBedLeavesTheVoiceClockAlone() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.setBed(tone())
        p.setBedVolume(0.5)
        p.enqueue(.silence(seconds: 2), tag: 1)
        p.play()
        try p.renderOffline(seconds: 0.5)
        #expect(abs(p.consumedSeconds - 0.5) < 0.05)
        #expect(p.queuedSeconds > 1.4)
    }

    @Test func theBedSurvivesAMediaServicesRebuild() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.setBed(tone())
        p.setBedVolume(0.5)
        p.rebuildAfterMediaServicesReset()
        try p.renderOffline(seconds: 0.2)
        #expect(p.lastRenderPeak > 0.1)
    }
}
