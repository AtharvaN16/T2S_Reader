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

    /// A voice that does not deliver Float32 — Int16 is plausible for the compact iOS voices — used
    /// to fail every utterance, which would render a whole book as 200 ms silences. Convert instead,
    /// at the voice's own sample rate (`resample` still moves it to the pipeline rate afterwards),
    /// and fail only when the conversion itself fails.
    static func float32Samples(from pcm: AVAudioPCMBuffer) throws -> [Float] {
        if pcm.format.commonFormat == .pcmFormatFloat32, let channel = pcm.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
        }
        guard pcm.frameLength > 0 else { return [] }
        guard let outFormat = AVAudioFormat(standardFormatWithSampleRate: pcm.format.sampleRate, channels: 1),
              let converter = AVAudioConverter(from: pcm.format, to: outFormat),
              let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: pcm.frameLength + 64)
        else { throw SynthesisError.failed("no converter for voice format \(pcm.format)") }
        // Same one-shot feed as `resample`: `convert` calls this synchronously on this thread only.
        final class Feed: @unchecked Sendable { var served = false }
        let feed = Feed()
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if feed.served { outStatus.pointee = .endOfStream; return nil }
            feed.served = true
            outStatus.pointee = .haveData
            return pcm
        }
        guard status != .error, let channel = output.floatChannelData?[0] else {
            throw SynthesisError.failed(conversionError?.localizedDescription ?? "voice format conversion failed")
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
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
        /// Owned as an optional and cleared in `finish`: the synthesizer holds the two callbacks and
        /// the callbacks hold the session, so leaving it set would retain an `AVSpeechSynthesizer`
        /// and the utterance's PCM for every utterance in the book.
        private(set) var synthesizer: AVSpeechSynthesizer?
        var sampleRate: Double = 0
        var samples: [Float] = []
        var markers: [Marker] = []
        var continuation: CheckedContinuation<Captured, any Error>?
        /// `write` can deliver nothing at all — a voice whose assets are not downloaded, an
        /// unauthorized Personal Voice — and the awaiting render job would then never complete, the
        /// serial scheduler would never advance, and playback would sit in `.catchingUp` forever.
        /// Spec §6 wants one failed utterance logged and filled with silence; this makes that reachable.
        var watchdog: Task<Void, Never>?

        init() { synthesizer = AVSpeechSynthesizer() }

        /// The watchdog fired: stop the synthesizer and fail this utterance.
        func timeOut() {
            synthesizer?.stopSpeaking(at: .immediate)
            finish(.failure(SynthesisError.failed("the voice did not finish within 60 s")))
        }

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
            let converted: [Float]
            do {
                converted = try SystemSpeechEngine.float32Samples(from: pcm)
            } catch {
                finish(.failure(error))
                return
            }
            if sampleRate == 0 { sampleRate = pcm.format.sampleRate }
            samples.append(contentsOf: converted)
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
            watchdog?.cancel()
            watchdog = nil
            continuation.resume(with: result)
            samples = []
            markers = []
            // Not synchronously: `AVSpeechSynthesizer` may still be inside the callback that got us here.
            Task { @MainActor in self.synthesizer = nil }
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
                session.synthesizer?.write(utterance, toBufferCallback: { buffer in
                    MainActor.assumeIsolated { session.receive(buffer) }
                }, toMarkerCallback: { markers in
                    MainActor.assumeIsolated { session.receive(markers) }
                })
                let watchdog = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else { return }     // `finish` cancelled us: the utterance landed
                    session.timeOut()
                }
                session.watchdog = watchdog
            }
        }
    }
}
