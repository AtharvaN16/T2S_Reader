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
    /// Completions collected on `AVAudioEngine`'s background completion thread and drained on the
    /// main actor by `renderOffline`. In manual-rendering mode there is no real run loop / app event
    /// cycle to hop back onto the main actor with (`renderOffline` is the only pump available, and it
    /// was confirmed empirically to not reliably drain a `Task { @MainActor in ... }` or
    /// `DispatchQueue.main.async` hop within its drain window in this environment), so `renderOffline`
    /// drains this queue directly and synchronously, from the main actor, after each render.
    private final class CompletionQueue: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(generation: Int, tag: Int)] = []
        func append(generation: Int, tag: Int) { lock.withLock { entries.append((generation, tag)) } }
        func drain() -> [(generation: Int, tag: Int)] { lock.withLock { let e = entries; entries.removeAll(); return e } }
        func removeAll() { lock.withLock { entries.removeAll() } }
    }
    private let manualCompletions = CompletionQueue()
    public private(set) var isPlaying = false
    public var onSegmentFinished: ((Int) -> Void)?

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
        manualAccumulatedSourceFrames += Double(max(0, out)) * rate
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
        let gen = generation
        // `.dataPlayedBack` fires when the buffer has reached real hardware presentation, which
        // doesn't exist in offline manual-rendering mode — it never fires there (confirmed
        // empirically). `.dataRendered` fires once the engine has produced the buffer's output
        // frames, which is the correct analog of "played" for manual rendering.
        let completionType: AVAudioPlayerNodeCompletionCallbackType = manual ? .dataRendered : .dataPlayedBack
        let isManual = manual
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: completionType) { [weak self] _ in
            guard let self else { return }
            if isManual {
                self.manualCompletions.append(generation: gen, tag: tag)
            } else {
                Task { @MainActor in
                    guard self.generation == gen else { return }
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
        manualCompletions.removeAll()
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
        // The completion callback fires asynchronously on a background thread shortly after the
        // render call returns; give it a moment to land before draining.
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        drainManualCompletions()
    }

    private func drainManualCompletions() {
        for entry in manualCompletions.drain() where entry.generation == generation {
            onSegmentFinished?(entry.tag)
        }
    }
}
