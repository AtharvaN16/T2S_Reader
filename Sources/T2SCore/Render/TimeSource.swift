import Foundation

public protocol TimeSource: Sendable {
    func now() -> TimeInterval
}

public struct SystemTimeSource: TimeSource {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// A clock tests move by hand.
public final class ManualTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval

    public init(_ start: TimeInterval = 0) { current = start }

    public func now() -> TimeInterval { lock.withLock { current } }
    public func advance(by seconds: TimeInterval) { lock.withLock { current += seconds } }
    public func set(_ t: TimeInterval) { lock.withLock { current = t } }
}
