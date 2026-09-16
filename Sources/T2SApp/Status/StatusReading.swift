// Sources/T2SApp/Status/StatusReading.swift
import Foundation

/// Which job is speaking. Identity, and the order the band picks between them: the voice
/// outranks everything because it is the one wait the reader can neither start nor stop, and
/// the one that blocks all audio until it ends. A render they asked for can wait its turn.
public enum StatusKind: Sendable, Hashable, CaseIterable {
    case voice, render, `import`

    /// Lower wins. Fixed, not configurable: a precedence a caller can set is a precedence that
    /// disagrees with itself somewhere.
    public var rank: Int {
        switch self {
        case .voice: 0
        case .render: 1
        case .import: 2
        }
    }
}

/// Everything the status band says, worked out from one job's state and nothing else.
///
/// This is `WarmUpReading`'s shape with the Kokoro phases lifted out of it. The warm-up keeps
/// its own phase mapping — that is the part that has been hard-won and tested — and hands one
/// of these over. A second job writes a resolver and says nothing about views.
public struct StatusReading: Sendable, Equatable {
    /// How the band is lit. `waiting` is the blue, `ready` the green, `failed` the amber.
    public enum Tone: Sendable, Hashable { case waiting, ready, failed }

    /// How long one message is held before the next, in seconds.
    public static let dwell: Double = 3.2
    /// Under this many seconds left there is nothing worth cycling: a message would be swapped
    /// once and the wait would be over.
    public static let cycleFloor = 12
    /// Past this much of the bar the cycle stops on its last message and stays there — "almost
    /// done" is the truest thing left, and rotating off it reads as the wait starting over.
    public static let stickPoint = 0.92
    /// How long the ending's colour takes to arrive, in seconds. The blue takes a second and a
    /// half to breathe in and the ending is eased over the same span, on the breath's own curve,
    /// rather than cutting in over a quarter-second — at that speed the green does not read as the
    /// wait finishing, it reads as a flash (owner, 2026-09-12).
    public static let readyEase: Double = 1.4

    public var kind: StatusKind
    /// Names what is happening. Never moves.
    public var title: String
    /// The cycle in the row beneath the title — the only thing that animates.
    public var messages: [String]
    /// The slot beside it: megabytes, a clock, "3 of 12". Never takes part in the cycle.
    public var value: String?
    /// 0…1 across the whole job, never retreating.
    public var progress: Double
    /// Relative segment widths for the bar. `[1]` is a plain bar.
    public var segments: [Double]
    public var tone: Tone
    /// Whether the subtext row closes rather than holding its height. True only at the very end,
    /// where nothing follows but the fade; every other empty row keeps its height, or the bar
    /// drops 13 pt and is pulled straight back.
    public var collapsesSubtext: Bool

    public init(kind: StatusKind, title: String, messages: [String] = [], value: String? = nil,
                progress: Double, segments: [Double] = [1], tone: Tone = .waiting,
                collapsesSubtext: Bool = false) {
        self.kind = kind
        self.title = title
        self.messages = messages
        self.value = value
        self.progress = min(1, max(0, progress))
        self.segments = segments
        self.tone = tone
        self.collapsesSubtext = collapsesSubtext
    }

    /// Which message is showing, `elapsed` seconds in. Nil when there is nothing to say. Past
    /// ``stickPoint`` the cycle stops on its last message rather than wrapping.
    public func message(elapsed: TimeInterval) -> String? {
        guard !messages.isEmpty else { return nil }
        guard messages.count > 1 else { return messages[0] }
        guard progress < Self.stickPoint else { return messages[messages.count - 1] }
        return messages[Int(max(0, elapsed) / Self.dwell) % messages.count]
    }
}
