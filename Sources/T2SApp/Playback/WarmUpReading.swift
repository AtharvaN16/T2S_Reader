// Sources/T2SApp/Playback/WarmUpReading.swift
import Foundation

/// Everything the warm-up line says, worked out from the wait's state and nothing else.
///
/// This is a plain value with no view and no engine in it, because every mistake the old line made
/// was a mistake of *resolution* rather than of drawing: a failed warm-up that read "Voice ready",
/// a retry countdown that never counted, an estimate shown before its clock had started. Those are
/// answerable in a test; a `body` is not. `WarmUpLine` maps `KokoroStatus` onto ``Phase`` and then
/// only draws what comes back.
///
/// **Three slots.** A `title` naming what is happening, which never moves. A `messages` cycle in
/// the row beneath it, which is the only thing that animates. And a `value` beside it — the
/// megabytes while a download runs, the clock once one is worth showing — which never takes part in
/// the cycle, because the time is the thing a waiting reader is looking for and it cannot be the
/// thing that rotates away (owner, 2026-09-12).
public struct WarmUpReading: Sendable {

    /// Which half of the one-time setup failed. The two want different words: a download will try
    /// again by itself next launch, a stage load will not.
    public enum Failure: Sendable, Hashable { case install, warmUp }

    /// The wait as the line needs to know it. Deliberately not `KokoroStatus`: this is the reader's
    /// view of the wait, where "warming for four minutes on an A13" and "warming for six seconds"
    /// are different situations and `.preparing` is one.
    public enum Phase: Sendable, Hashable {
        case checking
        case waitingForNetwork
        case downloading(received: Int, total: Int)
        /// A dropped file, retried. `secondsLeft` is a real scheduled delay, not a remembered guess,
        /// which is why it is the one countdown in the app that earns ticking digits.
        case retrying(secondsLeft: Int)
        case preparing(step: Int, of: Int, secondsLeft: Int?)
        /// `stalled` once the wait has run well past what this phone remembered, when the estimate
        /// has stopped being a fact about anything.
        case warming(secondsLeft: Int?, stalled: Bool)
        /// Heart from the mirrors is speaking while Heart installs on the phone; the glow stays up
        /// through that audio on purpose, and this is the only line that explains why.
        case hostedVoiceSpeaking(secondsLeft: Int?)
        case ready(buildingBackgroundSet: Bool)
        case failed(Failure)
    }

    /// How the line is lit. `WarmRim` reads this to pick between the blue, the green and the amber.
    public enum Tone: Sendable, Hashable { case waiting, ready, failed }

    /// How long one message is held before the next, in seconds.
    public static let dwell: Double = 3.2

    /// Under this many seconds left there is nothing worth cycling: a message would be swapped once
    /// and the wait would be over. The clock carries those launches alone.
    public static let cycleFloor = 12

    /// Past this much of the bar the cycle stops on its last message and stays there — "almost
    /// done" is the truest thing the line has left, and rotating off it to "one-time install" reads
    /// as the wait starting over (owner, 2026-09-12).
    public static let stickPoint = 0.92

    public let phase: Phase
    /// 0…1 across the whole launch, never retreating. On a failure this is where the wait reached.
    public let progress: Double
    /// Whether this launch paid for an install before the stages, which is what decides whether the
    /// bar has phases to divide into at all. An everyday six-second warm-up has one part, not three.
    public let afterAnInstall: Bool

    public init(phase: Phase, progress: Double, afterAnInstall: Bool = false) {
        self.phase = phase
        self.progress = min(1, max(0, progress))
        self.afterAnInstall = afterAnInstall
    }

    // MARK: what it says

    public var title: String {
        switch phase {
        case .checking: "Checking the voice"
        case .waitingForNetwork: "Waiting for Wi-Fi"
        case .downloading: "Downloading the voice"
        case .retrying: "Download interrupted"
        case .preparing: "Preparing the voice"
        case .warming(_, let stalled): stalled ? "Still warming up" : "Warming up the voice"
        case .hostedVoiceSpeaking: "Reading in the cloud voice"
        case .ready: "Voice ready"
        case .failed(.install): "Download failed"
        case .failed(.warmUp): "Voice unavailable"
        }
    }

    /// The download owns "one-time install" — it is only ever true of a download. The warm-up trades
    /// it for "will be faster next time", which is the same promise in the form a warm-up can keep,
    /// and is literally what `expectedWarmUpSeconds` remembers. Both end on "almost done", so
    /// wherever the cycle lands near the finish it lands on something true.
    private static let downloadCycle = ["one-time install", "it might take some time", "almost done"]
    private static let warmUpCycle = ["it might take some time", "will be faster next time", "almost done"]

    public var messages: [String] {
        switch phase {
        case .checking:
            []
        case .waitingForNetwork:
            ["one-time install"]
        case .downloading:
            Self.downloadCycle
        case .retrying:
            ["your place is kept"]
        case .preparing:
            Self.warmUpCycle
        case .warming(let left, let stalled):
            // The short-wait suppression is about the *whole* wait being brief, so it lifts once the
            // bar is nearly full: a long warm-up's last seconds still deserve "almost done", and
            // `left` alone cannot tell "six seconds all in" from "six seconds of four minutes".
            if stalled { ["it might take some time"] }
            else if let left, left < Self.cycleFloor, progress < Self.stickPoint { [] }
            else { Self.warmUpCycle }
        case .hostedVoiceSpeaking:
            Self.warmUpCycle
        case .ready(let building):
            building ? ["finishing up in the background"] : []
        case .failed(.install):
            ["it will try again next time"]
        case .failed(.warmUp):
            // The title alone leaves a reader wondering whether the book still reads aloud at all.
            // This is the only part that answers the question they actually have.
            ["reading in the system voice instead"]
        }
    }

    /// Which message is showing, `elapsed` seconds into this phase. Nil when there is nothing to
    /// say. Past ``stickPoint`` the cycle stops on its last message rather than wrapping.
    public func message(elapsed: TimeInterval) -> String? {
        let all = messages
        guard !all.isEmpty else { return nil }
        guard all.count > 1 else { return all[0] }
        guard progress < Self.stickPoint else { return all[all.count - 1] }
        let step = Int(max(0, elapsed) / Self.dwell)
        return all[step % all.count]
    }

    /// The slot beside the bar: megabytes while a download is running, a clock once one is backed by
    /// something real, and nothing at all when nothing is counting. A download's remaining time is
    /// the least trustworthy number the app has and the megabytes already say how far along it is,
    /// so the clock waits until the download is over.
    public var value: String? {
        switch phase {
        case .checking, .waitingForNetwork, .ready, .failed:
            nil
        case .downloading(let received, let total):
            "\(received) of \(total) MB"
        case .retrying(let left):
            "\(max(0, left))s"
        case .preparing(_, _, let left):
            Self.clock(left)
        case .warming(let left, let stalled):
            stalled ? nil : Self.clock(left)
        case .hostedVoiceSpeaking(let left):
            Self.clock(left)
        }
    }

    /// Seconds under a minute and a half, `m:ss` above it. A remembered 220 s once read as
    /// "about 220 s" on the owner's phone. Spent estimates return nil rather than counting down
    /// past zero — the line would rather say nothing than say something that has gone wrong.
    private static func clock(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        guard seconds >= 90 else { return "\(seconds)s" }
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    // MARK: how it looks

    public var tone: Tone {
        switch phase {
        case .ready: .ready
        case .failed: .failed
        default: .waiting
        }
    }

    /// Ready is the last thing that happens before the glow goes, so its empty subtext row closes
    /// rather than holding a gap under "Voice ready". Every other empty row keeps its height:
    /// something follows those, and a row that collapses and re-opens drops the bar 15 pt and pulls
    /// it straight back (owner, 2026-09-12).
    public var collapsesSubtext: Bool {
        messages.isEmpty && value == nil && tone == .ready
    }

    /// Relative segment widths for the bar. One entry is a plain bar. A download is one continuous
    /// byte count, so it stays plain; only once the install's phases are behind it does the bar
    /// divide — download, prepare, warm — proportioned to how long each really takes.
    public var segments: [Double] {
        switch phase {
        case .preparing, .hostedVoiceSpeaking:
            [46, 18, 18]
        case .warming, .ready, .failed(.warmUp):
            afterAnInstall ? [46, 18, 18] : [1]
        case .checking, .waitingForNetwork, .downloading, .retrying, .failed(.install):
            [1]
        }
    }
}
