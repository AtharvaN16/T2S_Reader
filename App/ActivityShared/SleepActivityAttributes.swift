import ActivityKit
import Foundation

/// The sleep timer card's wire format.
///
/// `deadline` is the whole point: a Live Activity view can count down from a `Date` on its own,
/// so a timed sleep needs no update between starting and firing. Nil means `.endOfChapter`,
/// which has no moment to count toward and must not appear to be counting.
struct SleepActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var headline: String
        var detail: String
        var deadline: Date?
    }

    var bookTitle: String
}
