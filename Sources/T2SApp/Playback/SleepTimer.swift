import Foundation
import Observation

public enum SleepOption: Hashable, Sendable {
    case minutes(Int)
    case endOfChapter

    /// Spec §2.4.5 chips.
    public static let all: [SleepOption] = [
        .minutes(10), .minutes(20), .minutes(30), .minutes(45), .minutes(60), .endOfChapter,
    ]

    public var chipLabel: String {
        switch self {
        case .minutes(let minutes): return "\(minutes) min"
        case .endOfChapter: return "End of chapter"
        }
    }
}

/// Spec §2.4.5: pauses playback when the time is up or the chapter ends; ends early if the document does.
/// Driven by the app's 10 Hz ticker; the clock is injected so tests do not wait.
@MainActor
@Observable
public final class SleepTimer {
    public private(set) var active: SleepOption?
    public private(set) var remainingSeconds: TimeInterval?

    private let player: PlayerModel
    private let clock: @Sendable () -> Date
    private var deadline: Date?
    private var chapterAtStart: Int?
    private var chapterTitleAtStart: String?

    public init(player: PlayerModel, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.player = player
        self.clock = clock
    }

    public var caption: String? {
        switch active {
        case .minutes:
            guard let remainingSeconds else { return nil }
            return "Ends in \(DurationFormatter.clock(remainingSeconds))"
        case .endOfChapter:
            guard let chapterTitleAtStart else { return nil }
            return "Until the end of \(chapterTitleAtStart)"
        case nil:
            return nil
        }
    }

    public func start(_ option: SleepOption) {
        active = option
        switch option {
        case .minutes(let minutes):
            deadline = clock().addingTimeInterval(TimeInterval(minutes * 60))
            remainingSeconds = TimeInterval(minutes * 60)
            chapterAtStart = nil
            chapterTitleAtStart = nil
        case .endOfChapter:
            deadline = nil
            remainingSeconds = nil
            chapterAtStart = player.chapterIndex
            if let chapterAtStart,
               let timeline = player.coordinator.timeline,
               timeline.chapters.indices.contains(chapterAtStart) {
                chapterTitleAtStart = timeline.chapters[chapterAtStart].title
            } else {
                chapterTitleAtStart = "this chapter"
            }
        }
    }

    public func cancel() {
        active = nil
        deadline = nil
        remainingSeconds = nil
        chapterAtStart = nil
        chapterTitleAtStart = nil
    }

    public func tick() {
        guard let active else { return }
        if player.state == .finished {
            cancel()
            return
        }
        switch active {
        case .minutes:
            guard let deadline else { return }
            let remaining = deadline.timeIntervalSince(clock())
            if remaining <= 0 {
                fire()
            } else {
                remainingSeconds = remaining
            }
        case .endOfChapter:
            if let chapterAtStart, let current = player.chapterIndex, current != chapterAtStart {
                fire()
            }
        }
    }

    private func fire() {
        if player.isPlaying {
            player.coordinator.pause()
        }
        cancel()
    }
}
