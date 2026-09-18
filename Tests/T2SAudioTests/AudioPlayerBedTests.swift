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

    /// One second of a 220 Hz tone at the manual engine's own rate (`PCMAudio.defaultSampleRate`,
    /// 24 kHz) — a loop at another rate than the bed's default 48 kHz connection, so `setBed` must
    /// disconnect and reconnect the node at the loop's own format.
    private func toneAtEngineRate() -> PCMAudio {
        let rate = PCMAudio.defaultSampleRate
        return PCMAudio(sampleRate: rate, samples: (0..<Int(rate)).map { Float(sin(Double($0) * 2 * .pi * 220 / rate)) * 0.5 })
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

    /// All eight beds are 48 kHz today, so the reconnect-at-another-rate branch in `setBed` is
    /// otherwise never exercised. A loop at the manual engine's own rate forces it.
    @Test func theBedIsHeardAfterReconnectingAtAnotherRate() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.setBed(toneAtEngineRate())
        p.setBedVolume(0.5)
        try p.renderOffline(seconds: 0.2)
        #expect(p.lastRenderPeak > 0.1)
    }
}
