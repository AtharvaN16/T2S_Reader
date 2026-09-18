import Foundation
import T2SCore

/// What plays the ambient bed under the voice (soundscape design §4.1). `AudioPlayer` is the real
/// one; the model that drives it sees only this, and tests hand it a recorder. Narrow on purpose:
/// the coordinator's `AudioPlaying` has no business with a bed.
@MainActor
public protocol BedPlaying: AnyObject {
    /// One mono loop, its seam already baked, or nil for none. A new loop starts from its start.
    func setBed(_ loop: PCMAudio?)
    /// 0…1 linear gain, applied at once. The model ramps; the player does not.
    func setBedVolume(_ volume: Float)
}
