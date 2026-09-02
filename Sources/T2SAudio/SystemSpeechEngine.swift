@preconcurrency import AVFoundation
import Foundation
import T2SCore

/// The spec §6 fallback engine (the system voice), and the only engine until Plan 5 lands Kokoro.
/// Offline synthesis through `AVSpeechSynthesizer.write`, resampled to the pipeline rate. Word
/// timings come from the synthesizer's markers when a voice provides them (the compact voices on
/// macOS do not); otherwise the result carries none and the highlighter degrades to
/// character-proportional timing (Plan 1).
public final class SystemSpeechEngine: SynthesisEngine {
    public let engineID = "system-speech"
    public let sampleRate: Double
    /// Used when the request's `voiceID` is not an `AVSpeechSynthesisVoice` identifier (e.g. "default").
    public let fallbackLanguage: String

    public init(sampleRate: Double = PCMAudio.defaultSampleRate, fallbackLanguage: String = "en-US") {
        self.sampleRate = sampleRate
        self.fallbackLanguage = fallbackLanguage
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        guard !request.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SynthesisError.failed("nothing to speak")
        }
        let captured = try await Self.speak(request.spoken, voiceID: request.voiceID, fallbackLanguage: fallbackLanguage)
        let audio = try Self.resample(captured.samples, from: captured.sampleRate, to: sampleRate)
        let timings = Self.timings(from: captured.markers, text: request.spoken,
                                   sampleRate: captured.sampleRate, totalSeconds: audio.duration)
        return SynthesisResult(audio: audio, wordTimings: timings)
    }

    // MARK: Markers → timings

    struct Marker: Hashable, Sendable {
        /// UTF-16 range into the spoken text.
        var range: Range<Int>
        /// Sample index into the synthesizer's own (unresampled) audio.
        var sampleOffset: Int
    }

    /// Each word runs from its marker to the next marker (or the end of the audio). Markers past
    /// the text are dropped; order follows the audio, not the marker delivery order.
    static func timings(from markers: [Marker], text: String, sampleRate: Double, totalSeconds: TimeInterval) -> [WordTiming] {
        let length = text.utf16.count
        let sorted = markers.filter { $0.range.upperBound <= length }.sorted { $0.sampleOffset < $1.sampleOffset }
        guard !sorted.isEmpty, sampleRate > 0 else { return [] }
        return sorted.indices.map { i in
            let start = min(totalSeconds, Double(sorted[i].sampleOffset) / sampleRate)
            let end = i + 1 < sorted.count ? min(totalSeconds, Double(sorted[i + 1].sampleOffset) / sampleRate) : totalSeconds
            return WordTiming(spokenRange: sorted[i].range, start: start, end: max(start, end))
        }
    }

    // MARK: Resampling

    static func resample(_ samples: [Float], from: Double, to: Double) throws -> PCMAudio {
        if abs(from - to) < 0.5 || samples.isEmpty { return PCMAudio(sampleRate: to, samples: samples) }
        guard let inFormat = AVAudioFormat(standardFormatWithSampleRate: from, channels: 1),
              let outFormat = AVAudioFormat(standardFormatWithSampleRate: to, channels: 1),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outFormat,
                                            frameCapacity: AVAudioFrameCount(Double(samples.count) * to / from) + 64)
        else { throw SynthesisError.failed("resampler unavailable for \(from) → \(to) Hz") }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            input.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        // `converter.convert` invokes this closure synchronously and only ever on the calling
        // thread, so the capture is safe despite the compiler's conservative `@Sendable` check.
        final class Feed: @unchecked Sendable { var served = false }
        let feed = Feed()
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if feed.served { outStatus.pointee = .endOfStream; return nil }
            feed.served = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error else {
            throw SynthesisError.failed(conversionError?.localizedDescription ?? "resample failed")
        }
        let out = Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
        return PCMAudio(sampleRate: to, samples: out)
    }

    // MARK: Speaking

    struct Captured: Sendable {
        var sampleRate: Double
        var samples: [Float]
        var markers: [Marker]
    }

    /// One `write` call. `AVSpeechSynthesizer` delivers its callbacks on the main run loop, so the
    /// session lives on the main actor and is retained by the callbacks until the final empty buffer.
    @MainActor
    private final class Session {
        let synthesizer = AVSpeechSynthesizer()
        var sampleRate: Double = 0
        var samples: [Float] = []
        var markers: [Marker] = []
        var continuation: CheckedContinuation<Captured, any Error>?

        func receive(_ buffer: AVAudioBuffer) {
            guard continuation != nil else { return }
            guard let pcm = buffer as? AVAudioPCMBuffer else {
                finish(.failure(SynthesisError.failed("unexpected buffer type \(type(of: buffer))")))
                return
            }
            if pcm.frameLength == 0 {
                if samples.isEmpty {
                    finish(.failure(SynthesisError.failed("the voice produced no audio")))
                } else {
                    finish(.success(Captured(sampleRate: sampleRate, samples: samples, markers: markers)))
                }
                return
            }
            guard pcm.format.commonFormat == .pcmFormatFloat32, let channel = pcm.floatChannelData?[0] else {
                finish(.failure(SynthesisError.failed("unsupported voice format \(pcm.format)")))
                return
            }
            if sampleRate == 0 { sampleRate = pcm.format.sampleRate }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
        }

        func receive(_ speechMarkers: [AVSpeechSynthesisMarker]) {
            let bytesPerSample = MemoryLayout<Float>.size
            for marker in speechMarkers where marker.mark == .word {
                let range = marker.textRange
                markers.append(Marker(range: range.location..<(range.location + range.length),
                                      sampleOffset: max(0, Int(marker.byteSampleOffset) / bytesPerSample)))
            }
        }

        private func finish(_ result: Result<Captured, any Error>) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }

    private static func speak(_ text: String, voiceID: String, fallbackLanguage: String) async throws -> Captured {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let session = Session()
                session.continuation = continuation
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID) ?? AVSpeechSynthesisVoice(language: fallbackLanguage)
                guard utterance.voice != nil else {
                    session.continuation = nil
                    continuation.resume(throwing: SynthesisError.failed("no system voice for \(fallbackLanguage)"))
                    return
                }
                session.synthesizer.write(utterance, toBufferCallback: { buffer in
                    MainActor.assumeIsolated { session.receive(buffer) }
                }, toMarkerCallback: { markers in
                    MainActor.assumeIsolated { session.receive(markers) }
                })
            }
        }
    }
}
