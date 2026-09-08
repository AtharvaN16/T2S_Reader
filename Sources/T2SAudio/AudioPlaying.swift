import Foundation
import T2SCore

/// What the coordinator needs from a player. `AudioPlayer` is the real one; tests use a fake.
@MainActor
public protocol AudioPlaying: AnyObject {
    /// 0.5…4.0 with pitch correction (spec §3.5).
    var rate: Double { get set }
    var isPlaying: Bool { get }
    /// Audio consumed since the last `reset`, in seconds at 1x, independent of `rate`.
    var consumedSeconds: TimeInterval { get }
    /// Audio scheduled but not yet consumed, in seconds at 1x: zero when the player has run dry —
    /// which a streamed head can, between its pieces (Plan 16).
    var queuedSeconds: TimeInterval { get }
    /// Called with the segment's tag after its last frame has played.
    var onSegmentFinished: ((Int) -> Void)? { get set }
    /// Appends audio for gapless playback after whatever is queued. A segment — one utterance, one
    /// `tag` — may arrive as several buffers while it streams; `onSegmentFinished` fires once, after
    /// the buffer enqueued with `isFinal`.
    func enqueue(_ audio: PCMAudio, tag: Int, isFinal: Bool)
    func play()
    func pause()
    /// Stops, drops every queued segment, and zeroes `consumedSeconds`.
    func reset()
    /// The only destructive hardware recovery operation. The coordinator immediately resets and
    /// refills from its persisted Position, so implementations must not retain scheduled buffers.
    func rebuildAfterMediaServicesReset()
}

public extension AudioPlaying {
    /// A whole segment in one buffer.
    func enqueue(_ audio: PCMAudio, tag: Int) { enqueue(audio, tag: tag, isFinal: true) }
}
