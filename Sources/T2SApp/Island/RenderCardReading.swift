import Foundation

/// Everything the render Live Activity says, worked out from the queue and nothing else.
///
/// This is `StatusReading`'s shape and its reason: a plain value the views cannot disagree
/// with, tested on the Mac without a simulator. It holds no ActivityKit type, because the
/// package builds for macOS and ActivityKit does not exist there.
///
/// **Why the queue and not one chapter.** Away from the phone the question is "is my book
/// ready", not "how is chapter 4". And `BookSheet` commits a multi-select batch, so one
/// activity per chapter would start and end eight times against a system cap on how many can
/// be live at once.
public struct RenderCardReading: Equatable, Sendable {
    public var headline: String
    public var detail: String
    public var ready: Int
    public var total: Int
    /// Chapters done over chapters asked for. Deliberately not the running chapter's utterance
    /// fraction: a bar that steps once a chapter is honest about what it knows, where one that
    /// glides and then stalls between chapters is not.
    public var fraction: Double
    /// Whether this update should break through — expand the island, put a banner on the Lock
    /// Screen, buzz. Only a finished chapter does.
    public var alerts: Bool
    /// The last thing the card will ever say, after which it dismisses itself.
    public var isFinished: Bool

    public init(headline: String, detail: String, ready: Int, total: Int,
                fraction: Double, alerts: Bool, isFinished: Bool) {
        self.headline = headline
        self.detail = detail
        self.ready = ready
        self.total = total
        self.fraction = fraction
        self.alerts = alerts
        self.isFinished = isFinished
    }

    /// - Parameter justFinished: the display name of a chapter that finished on this very
    ///   update, or nil on a resting update. Non-nil is what makes the card alert.
    public static func make(jobs: [ChapterRenderJob], bookTitle: String,
                            hold: ChapterRenderRunner.Hold?,
                            justFinished: String?) -> RenderCardReading? {
        guard !jobs.isEmpty else { return nil }
        let total = jobs.count
        let ready = jobs.filter { if case .ready = $0.state { return true } else { return false } }.count
        let failed = jobs.filter { if case .failed = $0.state { return true } else { return false } }.count
        let settled = ready + failed
        let fraction = Double(settled) / Double(total)
        let tally = "\(ready) of \(total) chapters ready"

        if settled == total {
            return RenderCardReading(headline: "\(bookTitle) is ready",
                                     detail: "\(ready) chapters ready",
                                     ready: ready, total: total, fraction: 1,
                                     alerts: true, isFinished: true)
        }
        if let hold {
            return RenderCardReading(headline: bookTitle, detail: sentence(for: hold),
                                     ready: ready, total: total, fraction: fraction,
                                     alerts: false, isFinished: false)
        }
        if let justFinished {
            return RenderCardReading(headline: "\(justFinished) is ready", detail: tally,
                                     ready: ready, total: total, fraction: fraction,
                                     alerts: true, isFinished: false)
        }
        return RenderCardReading(headline: bookTitle, detail: tally, ready: ready, total: total,
                                 fraction: fraction, alerts: false, isFinished: false)
    }

    /// The hold's own sentence. None of these is an error and none of them alerts: the queue
    /// stopped for a reason the reader either chose or cannot argue with.
    private static func sentence(for hold: ChapterRenderRunner.Hold) -> String {
        switch hold {
        case .byReader: "Paused"
        case .hot: "Paused while the phone cools"
        case .storeFull: "Paused — storage is full"
        }
    }
}
