import AVFoundation
import Foundation
import T2SCore

/// Spec §3.5: AVAudioEngine → AVAudioPlayerNode → AVAudioUnitTimePitch → mainMixer.
@MainActor
public final class AudioPlayer: AudioPlaying {
    public enum Error: Swift.Error { case badFormat }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format: AVAudioFormat
    private let manual: Bool
    /// Frames scheduled since the last reset, used to freeze `consumedSeconds` when the queue drains.
    private var scheduledFrames: AVAudioFramePosition = 0
    /// `engine.manualRenderingSampleTime` at the last fold point (reset or rate change) — manual
    /// mode's `consumedSeconds` baseline for the *current* rate interval.
    /// `player.lastRenderTime`/`playerTime(forNodeTime:)` is unusable for this: with `AVAudioUnitTimePitch`
    /// in the chain it reports the player's own *pull* position, which the time-pitch unit's internal
    /// look-ahead buffer pulls ahead of the true rendered-output position by a fixed amount (confirmed
    /// empirically: with the time-pitch node removed, `nodeTime.sampleTime` matches
    /// `engine.manualRenderingSampleTime` exactly; with it present, it consistently reads ~1824 frames high
    /// at 24 kHz, even at rate 1.0). `engine.manualRenderingSampleTime` tracks true rendered output frames.
    private var manualBaseline: AVAudioFramePosition = 0
    /// Source seconds (at 1x) folded in from prior rate intervals since the last reset. Needed
    /// because `consumedSeconds` must integrate progress per rate interval, not apply the
    /// *current* rate retroactively to the whole span since reset — see `foldManualProgress()`.
    private var manualAccumulatedSourceFrames: Double = 0
    private var generation = 0
    /// Manual mode only: segments in schedule order with the cumulative source-frame count at
    /// which each one ends. `deliverManualCompletions()` walks this from the front and fires
    /// `onSegmentFinished` for every segment whose end has been consumed so far — computed
    /// directly from the render clock (`manualAccumulatedSourceFrames` /
    /// `engine.manualRenderingSampleTime`), not observed from AVAudioEngine's completion
    /// callbacks. The player already knows exactly how many source frames it has consumed, so
    /// there's no need to wait on a background-thread callback whose delivery relative to
    /// `renderOffline`'s return is not guaranteed — that race is what made completions land late
    /// under CPU contention (confirmed empirically: intermittent under concurrent test-suite load,
    /// never under an isolated run).
    private var manualSegments: [(tag: Int, endSourceFrames: Double)] = []
    public private(set) var isPlaying = false
    public var onSegmentFinished: ((Int) -> Void)?

    /// The time-pitch unit's processing latency: presented audio lags the source position it was
    /// derived from by this many seconds. Plan 4 subtracts it from the playhead when placing
    /// highlights against real hardware output.
    public var outputLatencySeconds: TimeInterval { Double(timePitch.latency) }

    public var rate: Double {
        get { Double(timePitch.rate) }
        set {
            foldManualProgress()
            timePitch.rate = Float(max(0.5, min(4.0, newValue)))
        }
    }

    public init(sampleRate: Double = PCMAudio.defaultSampleRate, manualRendering: Bool = false) throws {
        guard let f = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { throw Error.badFormat }
        format = f
        manual = manualRendering
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        if manualRendering {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        }
        try engine.start()
    }

    /// Manual mode: folds the output rendered so far at the current rate into the accumulator and
    /// restarts the baseline, so a later rate change cannot retroactively rescale it.
    private func foldManualProgress() {
        guard manual else { return }
        let out = engine.manualRenderingSampleTime - manualBaseline
        manualAccumulatedSourceFrames = min(manualAccumulatedSourceFrames + Double(max(0, out)) * rate, Double(scheduledFrames))
        manualBaseline = engine.manualRenderingSampleTime
    }

    public var consumedSeconds: TimeInterval {
        let rawFrames: Double
        if manual {
            // `engine.manualRenderingSampleTime` is exact rendered-output time, but it's in the
            // engine's fixed processing-rate domain, not source-domain — it doesn't reflect the
            // time-pitch rate multiplier, so scale by `rate` to get source seconds at 1x. Progress
            // from earlier rate intervals is already folded into `manualAccumulatedSourceFrames`
            // (see `foldManualProgress()`), so only the current interval needs scaling here.
            rawFrames = manualAccumulatedSourceFrames + Double(max(0, engine.manualRenderingSampleTime - manualBaseline)) * rate
        } else {
            guard let nodeTime = player.lastRenderTime, let t = player.playerTime(forNodeTime: nodeTime) else { return 0 }
            rawFrames = Double(t.sampleTime)
        }
        let frames = min(rawFrames, Double(scheduledFrames))
        return max(0, frames) / format.sampleRate
    }

    public func enqueue(_ audio: PCMAudio, tag: Int) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        if !audio.samples.isEmpty {
            audio.samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress!, count: audio.samples.count)
            }
        }
        scheduledFrames += AVAudioFramePosition(audio.samples.count)
        if manual {
            // Manual mode computes completions from the render clock in `deliverManualCompletions()`
            // rather than observing AVAudioEngine's completion callback — see `manualSegments`'s doc
            // comment. No completion handler is scheduled at all.
            manualSegments.append((tag: tag, endSourceFrames: Double(scheduledFrames)))
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        } else {
            let gen = generation
            // `.dataPlayedBack` fires when the buffer has reached real hardware presentation — the
            // correct "played" signal for real playback, where a functioning run loop / app event
            // cycle services the `Task { @MainActor in ... }` hop below.
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == gen else { return }
                    self.onSegmentFinished?(tag)
                }
            }
        }
    }

    public func play() {
        player.play()
        isPlaying = true
    }

    public func pause() {
        player.pause()
        isPlaying = false
    }

    public func reset() {
        generation += 1
        player.stop()
        scheduledFrames = 0
        if manual { manualBaseline = engine.manualRenderingSampleTime }
        manualAccumulatedSourceFrames = 0
        manualSegments.removeAll()
        isPlaying = false
    }

    /// Manual rendering only: advances the offline engine by `seconds` of output.
    func renderOffline(seconds: TimeInterval) throws {
        precondition(manual, "renderOffline requires manualRendering")
        guard let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else { return }
        var remaining = AVAudioFrameCount((seconds * format.sampleRate).rounded())
        while remaining > 0 {
            let n = min(remaining, engine.manualRenderingMaximumFrameCount)
            let status = try engine.renderOffline(n, to: out)
            guard status == .success || status == .insufficientDataFromInputNode else { break }
            remaining -= n
        }
        deliverManualCompletions()
    }

    /// Manual mode: fires completions for every leading segment whose end lies at or before the
    /// source frames consumed so far. Deterministic — no dependency on AVFoundation's callbacks.
    private func deliverManualCompletions() {
        let consumed = manualAccumulatedSourceFrames + Double(max(0, engine.manualRenderingSampleTime - manualBaseline)) * rate
        while let first = manualSegments.first, first.endSourceFrames <= consumed + 0.5 {
            manualSegments.removeFirst()
            onSegmentFinished?(first.tag)
        }
    }
}
