import AVFoundation
import Foundation
import T2SAudio
import T2SCore

/// Turns a `Soundscape` into the mono loop the bed plays: a recording decoded from the bundle, or
/// a noise made on the spot — either way seamed and brought to the common loudness (soundscape
/// design §4.2). A protocol, so the model's tests hand it a loop of ten samples.
public protocol SoundscapeLoading: Sendable {
    func load(_ soundscape: Soundscape) async -> PCMAudio?
}

/// `Bundle` is not marked `Sendable` but is documented thread-safe, and this reads one URL from it.
public final class BundleSoundscapeLoader: SoundscapeLoading, @unchecked Sendable {
    private let bundle: Bundle

    public init(bundle: Bundle) { self.bundle = bundle }

    public func load(_ soundscape: Soundscape) async -> PCMAudio? {
        let raw: PCMAudio?
        switch soundscape.source {
        case .noise(let colour):
            raw = NoiseLoop.make(colour)
        case .recording(let resource):
            guard let url = bundle.url(forResource: resource, withExtension: "m4a") else { return nil }
            raw = await Task.detached(priority: .userInitiated) { Self.decodeMono(url) }.value
        }
        guard let raw else { return nil }
        return Loudness.normalised(LoopSeam.bake(raw))
    }

    /// The file's samples mixed down to one channel, at the file's own rate.
    static func decodeMono(_ url: URL) -> PCMAudio? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let data = buffer.floatChannelData else { return nil }
        let channels = Int(file.processingFormat.channelCount)
        let n = Int(buffer.frameLength)
        guard channels > 0, n > 0 else { return nil }
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<channels {
            let channel = data[c]
            for i in 0..<n { mono[i] += channel[i] }
        }
        if channels > 1 {
            let k = 1 / Float(channels)
            for i in 0..<n { mono[i] *= k }
        }
        return PCMAudio(sampleRate: file.processingFormat.sampleRate, samples: mono)
    }
}
