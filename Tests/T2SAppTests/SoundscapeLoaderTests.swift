import AVFoundation
import Foundation
import Testing
import T2SAudio
import T2SCore
@testable import T2SApp

@Suite struct SoundscapeLoaderTests {
    @Test func aNoiseLoadsSeamedAndAtTheCommonLoudness() async throws {
        let loader = BundleSoundscapeLoader(bundle: .main)
        let loop = await loader.load(Soundscape.named("brown")!)
        let samples = try #require(loop).samples
        // 30 s at 48 kHz less the 2 s seam.
        #expect(samples.count == 28 * 48_000)
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        #expect(abs(Loudness.decibels(rms) - (-20)) < 0.5)
    }

    @Test func aStereoFileDecodesToMonoAtItsOwnRate() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bed-\(UUID().uuidString).caf")
        do {
            // Scoped: the write handle must close — flushing its converter buffer to the CAF
            // header — before decodeMono reads the same URL back; `write(from:)` alone does not
            // guarantee that, and an unscoped handle survives to the end of a debug-build test.
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
            buffer.frameLength = 4410
            for i in 0..<4410 {
                buffer.floatChannelData![0][i] = 0.4                          // left
                buffer.floatChannelData![1][i] = 0.2                          // right
            }
            try file.write(from: buffer)
        }
        let mono = try #require(BundleSoundscapeLoader.decodeMono(url))
        #expect(mono.sampleRate == 44_100 && mono.samples.count == 4410)
        #expect(abs(mono.samples[100] - 0.3) < 1e-4)                          // the mean of the two
    }

    @Test func aMissingRecordingIsNil() async {
        let loader = BundleSoundscapeLoader(bundle: .main)                   // the package's bundle has no .m4a
        let loop = await loader.load(Soundscape.named("rain")!)
        #expect(loop == nil)
    }
}
