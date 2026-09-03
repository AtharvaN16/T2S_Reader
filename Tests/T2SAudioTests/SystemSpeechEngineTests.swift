import AVFoundation
import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@Suite struct SystemSpeechEngineTests {
    @Test func timingsFollowMarkersAndCloseAtTheEnd() {
        let text = "Hello brave new world"
        let markers = [
            SystemSpeechEngine.Marker(range: 6..<11, sampleOffset: 11_025),     // "brave" at 0.5 s (22 050 Hz)
            SystemSpeechEngine.Marker(range: 0..<5, sampleOffset: 0),            // "Hello" at 0 s, out of order
            SystemSpeechEngine.Marker(range: 12..<15, sampleOffset: 22_050),     // "new" at 1.0 s
            SystemSpeechEngine.Marker(range: 16..<40, sampleOffset: 33_075),     // past the text: dropped
        ]
        let t = SystemSpeechEngine.timings(from: markers, text: text, sampleRate: 22_050, totalSeconds: 1.4)
        #expect(t.map(\.spokenRange) == [0..<5, 6..<11, 12..<15])
        #expect(t.map(\.start) == [0, 0.5, 1.0])
        #expect(t.map(\.end) == [0.5, 1.0, 1.4])
        #expect(SystemSpeechEngine.timings(from: [], text: text, sampleRate: 22_050, totalSeconds: 1).isEmpty)
    }

    @Test func resampleKeepsDurationAndLevel() throws {
        let from = 22_050.0, to = 24_000.0
        let sine = (0..<22_050).map { Float(sin(Double($0) * 2 * .pi * 440 / from)) * 0.5 }
        let out = try SystemSpeechEngine.resample(sine, from: from, to: to)
        #expect(out.sampleRate == to)
        #expect(abs(out.samples.count - 24_000) <= 64)
        let rms = (out.samples.reduce(0) { $0 + $1 * $1 } / Float(out.samples.count)).squareRoot()
        #expect(abs(rms - 0.3536) < 0.02)                                   // 0.5 / √2
        let same = try SystemSpeechEngine.resample(sine, from: from, to: from)
        #expect(same.samples == sine)
    }

    /// A voice that delivers Int16 must be converted, not rejected: rejecting would fail every
    /// utterance and render a whole book as 200 ms silences.
    @Test func int16BuffersAreConvertedRatherThanRejected() throws {
        let rate = 22_050.0
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_000))
        buffer.frameLength = 1_000
        let channel = try #require(buffer.int16ChannelData?[0])
        for i in 0..<1_000 { channel[i] = Int16(Double(Int16.max) * 0.5 * sin(Double(i) * 2 * .pi * 440 / rate)) }
        let samples = try SystemSpeechEngine.float32Samples(from: buffer)
        #expect(samples.count == 1_000)
        #expect(abs((samples.map(abs).max() ?? 0) - 0.5) < 0.02)              // full-scale Int16 → ±1.0 Float32

        let float = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let passthrough = try #require(AVAudioPCMBuffer(pcmFormat: float, frameCapacity: 4))
        passthrough.frameLength = 4
        for i in 0..<4 { passthrough.floatChannelData![0][i] = Float(i) / 4 }
        #expect(try SystemSpeechEngine.float32Samples(from: passthrough) == [0, 0.25, 0.5, 0.75])
    }

    @Test func synthesizesAudibleAudioAtThePipelineRate() async throws {
        guard !AVSpeechSynthesisVoice.speechVoices().isEmpty else { return }   // no voices installed: nothing to test
        let engine = SystemSpeechEngine()
        let result = try await engine.synthesize(SynthesisRequest(spoken: "Hello world, this is a test.", voiceID: "default"))
        #expect(result.audio.sampleRate == PCMAudio.defaultSampleRate)
        #expect(result.audio.duration > 0.5 && result.audio.duration < 6)
        #expect(result.audio.samples.map(abs).max() ?? 0 > 0.01)             // not silence
        for (a, b) in zip(result.wordTimings, result.wordTimings.dropFirst()) {
            #expect(a.start <= b.start && a.end <= result.audio.duration)
        }
        #expect(engine.engineID == "system-speech")
    }

    @Test func emptyTextFails() async throws {
        guard !AVSpeechSynthesisVoice.speechVoices().isEmpty else { return }
        await #expect(throws: SynthesisError.self) {
            _ = try await SystemSpeechEngine().synthesize(SynthesisRequest(spoken: "   ", voiceID: "default"))
        }
    }
}
