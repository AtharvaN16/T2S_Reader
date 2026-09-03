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
    /// Called with the segment's tag after its last frame has played.
    var onSegmentFinished: ((Int) -> Void)? { get set }
    /// Appends a segment for gapless playback after whatever is queued.
    func enqueue(_ audio: PCMAudio, tag: Int)
    func play()
    func pause()
    /// Stops, drops every queued segment, and zeroes `consumedSeconds`.
    func reset()
    /// The only destructive hardware recovery operation. The coordinator immediately resets and
    /// refills from its persisted Position, so implementations must not retain scheduled buffers.
    func rebuildAfterMediaServicesReset()
}
