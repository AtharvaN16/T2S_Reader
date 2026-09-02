import Foundation
import T2SCore
@testable import T2SAudio

/// Deterministic player: `advance(seconds:)` consumes audio at 1x and fires segment callbacks.
@MainActor
final class FakePlayer: AudioPlaying {
    var rate: Double = 1
    private(set) var isPlaying = false
    private(set) var consumedSeconds: TimeInterval = 0
    var onSegmentFinished: ((Int) -> Void)?
    private(set) var queue: [(tag: Int, remaining: TimeInterval)] = []
    private(set) var enqueuedTags: [Int] = []
    private(set) var resets = 0
    /// Seconds of audio still queued (the head clip's remainder plus every later segment).
    var queuedRemaining: TimeInterval { queue.reduce(0) { $0 + $1.remaining } }

    func enqueue(_ audio: PCMAudio, tag: Int) {
        queue.append((tag, audio.duration))
        enqueuedTags.append(tag)
    }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func reset() { queue.removeAll(); consumedSeconds = 0; isPlaying = false; resets += 1 }

    func advance(seconds: TimeInterval) {
        guard isPlaying else { return }
        var left = seconds
        while left > 0, !queue.isEmpty {
            let step = min(left, queue[0].remaining)
            consumedSeconds += step
            queue[0].remaining -= step
            left -= step
            if queue[0].remaining <= 1e-9 {
                let tag = queue.removeFirst().tag
                onSegmentFinished?(tag)
            }
        }
    }
}
