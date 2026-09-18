import Foundation

/// A straight line in decibels from one level to another over a duration (soundscape design
/// §4.2): a fade that is linear in dB sounds even from start to end, where one linear in gain
/// would be all over in its first tenth.
public struct GainRamp: Equatable, Sendable {
    public var from: Float
    public var to: Float
    public var start: Date
    public var duration: TimeInterval

    public init(from: Float, to: Float, start: Date, duration: TimeInterval) {
        self.from = from
        self.to = to
        self.start = start
        self.duration = duration
    }

    public func value(at now: Date) -> Float {
        guard duration > 0 else { return to }
        let t = min(1, max(0, now.timeIntervalSince(start) / duration))
        return from + (to - from) * Float(t)
    }

    public func isDone(at now: Date) -> Bool {
        now.timeIntervalSince(start) >= duration
    }
}
