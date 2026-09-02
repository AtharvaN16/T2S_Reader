import Foundation

/// Runtime-only position (spec §3.2). Never persisted.
public struct Playhead: Hashable, Sendable {
    public var utteranceIndex: Int
    /// Seconds into the utterance at 1x.
    public var offset: TimeInterval

    public init(utteranceIndex: Int, offset: TimeInterval = 0) {
        self.utteranceIndex = utteranceIndex
        self.offset = offset
    }
}

extension Playhead: Comparable {
    public static func < (a: Playhead, b: Playhead) -> Bool {
        a.utteranceIndex != b.utteranceIndex ? a.utteranceIndex < b.utteranceIndex : a.offset < b.offset
    }
}
