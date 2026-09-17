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
    /// What just happened, if anything. Nil is a resting update — a batch starting, a hold
    /// arriving, a number moving — and never alerts.
    ///
    /// A failure carries its own two lines rather than a name, because a reader away from the
    /// phone is owed the reason: "Chapter couldn't be rendered" over "The store is full".
    /// Before this, a chapter that failed while the app was backgrounded was announced nowhere
    /// at all, ever (review I6).
    public enum Event: Equatable, Sendable {
        /// The display name of a chapter that finished on this very update.
        case finished(name: String)
        case failed(title: String, reason: String)
    }

    public var headline: String
    public var detail: String
    public var ready: Int
    public var total: Int
    /// Chapters done over chapters asked for. Deliberately not the running chapter's utterance
    /// fraction: a bar that steps once a chapter is honest about what it knows, where one that
    /// glides and then stalls between chapters is not.
    public var fraction: Double
    /// Whether this update should break through — expand the island, put a banner on the Lock
    /// Screen, buzz. Only an event does, and only when the caller says it may.
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

    /// The jobs the card is allowed to count.
    ///
    /// `ChapterRenderRunner.queue` is every job of the whole session, across every document,
    /// until `cancelAll()`. Counting all of them made the second batch of a session name the
    /// *first* batch's book and tally the two together (review C3). The card is about exactly
    /// one book: the one the event belongs to when the caller knows it, else the one currently
    /// running, else the one asked for most recently.
    ///
    /// - Returns: that one document's jobs, in the order they were asked for; empty when the
    ///   queue is.
    public static func focus(_ jobs: [ChapterRenderJob],
                             preferring documentID: UUID? = nil) -> [ChapterRenderJob] {
        let wanted = documentID
            ?? jobs.first(where: { $0.state == .running })?.documentID
            ?? jobs.last?.documentID
        guard let wanted else { return [] }
        return jobs.filter { $0.documentID == wanted }
    }

    /// - Parameter jobs: one document's jobs — put the queue through ``focus(_:preferring:)``
    ///   first, or the card names whichever book the session happened to start with.
    /// - Parameter event: what happened on this very update, or nil on a resting one.
    /// - Parameter canAlert: whether this update is *allowed* to break through. False while the
    ///   app is on screen: the capsule is already saying it there, and never both (owner,
    ///   2026-09-16). No reading alerts when this is false, whatever else is true.
    public static func make(jobs: [ChapterRenderJob], bookTitle: String,
                            hold: ChapterRenderRunner.Hold?,
                            event: Event?,
                            canAlert: Bool) -> RenderCardReading? {
        guard !jobs.isEmpty else { return nil }
        let total = jobs.count
        let ready = jobs.filter { if case .ready = $0.state { return true } else { return false } }.count
        let failed = jobs.filter { if case .failed = $0.state { return true } else { return false } }.count
        let settled = ready + failed
        let fraction = Double(settled) / Double(total)
        let tally = "\(ready) of \(total) \(chapters(total)) ready"

        if settled == total {
            // Nothing survived. "<book> is ready" over a batch where every chapter failed is the
            // one thing this branch must never say (review M1).
            if ready == 0 {
                return RenderCardReading(headline: "\(bookTitle) couldn't be rendered",
                                         detail: "\(failed) \(chapters(failed)) failed",
                                         ready: 0, total: total, fraction: 1,
                                         alerts: canAlert, isFinished: true)
            }
            return RenderCardReading(headline: "\(bookTitle) is ready",
                                     detail: "\(ready) \(chapters(ready)) ready",
                                     ready: ready, total: total, fraction: 1,
                                     alerts: canAlert, isFinished: true)
        }
        if let hold {
            return RenderCardReading(headline: bookTitle, detail: sentence(for: hold),
                                     ready: ready, total: total, fraction: fraction,
                                     alerts: false, isFinished: false)
        }
        switch event {
        case .finished(let name):
            return RenderCardReading(headline: "\(name) is ready", detail: tally,
                                     ready: ready, total: total, fraction: fraction,
                                     alerts: canAlert, isFinished: false)
        case .failed(let title, let reason):
            return RenderCardReading(headline: title, detail: reason,
                                     ready: ready, total: total, fraction: fraction,
                                     alerts: canAlert, isFinished: false)
        case nil:
            return RenderCardReading(headline: bookTitle, detail: tally, ready: ready,
                                     total: total, fraction: fraction,
                                     alerts: false, isFinished: false)
        }
    }

    /// "1 chapter", "8 chapters". The card read "1 chapters ready" until 2026-09-16.
    private static func chapters(_ count: Int) -> String {
        count == 1 ? "chapter" : "chapters"
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
