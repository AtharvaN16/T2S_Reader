import Foundation

/// Everything the sleep timer's Live Activity says.
///
/// **It hands over a `Date`, not a count.** A Live Activity can count down from a stored date
/// entirely on its own, so a timed sleep costs nothing to keep current: the app never wakes,
/// there is no update budget to manage and no battery to spend. `.endOfChapter` has no such
/// date and says which chapter instead — a card that appeared to be counting toward a moment
/// nobody can name would be lying.
public struct SleepCardReading: Equatable, Sendable {
    public var headline: String
    public var detail: String
    /// When playback stops, for a view that ticks by itself. Nil for `.endOfChapter`.
    public var deadline: Date?

    public init(headline: String, detail: String, deadline: Date?) {
        self.headline = headline
        self.detail = detail
        self.deadline = deadline
    }

    public static func make(option: SleepOption?, deadline: Date?,
                            chapterTitle: String?) -> SleepCardReading? {
        guard let option else { return nil }
        switch option {
        case .minutes:
            // A timed sleep without a deadline cannot be drawn honestly, and a card that showed
            // no end would sit on the Lock Screen until iOS timed it out.
            guard let deadline else { return nil }
            return SleepCardReading(headline: "Sleep timer",
                                    detail: "Playback stops when the time is up",
                                    deadline: deadline)
        case .endOfChapter:
            return SleepCardReading(headline: "Sleep timer",
                                    detail: "Until the end of \(chapterTitle ?? "this chapter")",
                                    deadline: nil)
        }
    }
}
