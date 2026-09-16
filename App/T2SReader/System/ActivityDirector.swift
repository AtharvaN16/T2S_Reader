import ActivityKit
import Foundation
import T2SApp

/// Starts, updates and ends the app's Live Activities.
///
/// One object for both so there is one place that knows whether an activity exists, and one
/// place that decides an update should break through. A reading with `alerts` set gets an
/// `AlertConfiguration`, which is what expands the island and puts a banner on the Lock Screen;
/// everything else changes the card silently under the reader's thumb.
///
/// `Activity<Attributes>` is a plain class with no `Sendable` conformance, and ActivityKit's
/// `update`/`end` run on their own executor rather than the caller's — so the activity itself can
/// never cross off the main actor, not even as a `let` bound just before the `await` and the
/// stored property nilled out first. (That is the usual fix for handing a non-Sendable value out
/// of an actor, and it does not help here: Swift's region checker still treats a value read out of
/// a mutable main-actor property as tied to the main actor for the rest of the function, so
/// `sending` it into `update`/`end` is rejected regardless.) What *can* cross is the activity's
/// `id`, which is a plain `String`. `Activity<Attributes>.activities` — ActivityKit's own registry
/// of everything currently running — is how the two `apply...Update`/`apply...End` helpers below
/// turn that `id` back into a live `Activity` from inside a `nonisolated` function, so nothing
/// non-Sendable ever leaves the main actor.
///
/// Nothing here decides *what* the card says. That is `RenderCardReading` and
/// `SleepCardReading`, which are plain values and are tested.
@MainActor
final class ActivityDirector {
    private var renderID: String?
    /// The book the live render card names. Its attributes are fixed once requested, so this is
    /// how the director knows an update would be about a different book than the card says.
    private var renderBookTitle: String?
    private var sleepID: String?
    /// Whether this launch has already looked at what is on the Lock Screen. See ``adoptExisting``.
    private var hasAdopted = false

    private var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Takes over whatever this app left running on a previous launch, once.
    ///
    /// A Live Activity outlives the process that requested it: force-quit or crash mid-batch and
    /// the card is still on the Lock Screen when the app comes back. `renderID`/`sleepID` start
    /// nil every launch, so without this the next batch requested a *second* card and the first
    /// was orphaned until the system timed it out hours later — and nothing could ever end it,
    /// because ending needs the id (review I4). Adopting also gives the first `updateRender(nil)`
    /// of a fresh launch something to end, which is how a stale card actually clears.
    ///
    /// One of each is kept and any extras are ended: two cards for one app is the state this is
    /// here to get out of, not one to preserve.
    private func adoptExisting() {
        guard !hasAdopted else { return }
        hasAdopted = true
        let renders = Activity<RenderActivityAttributes>.activities
        renderID = renders.first?.id
        renderBookTitle = renders.first?.attributes.bookTitle
        for extra in renders.dropFirst() {
            let id = extra.id
            Task { await Self.applyRenderEnd(id: id, after: .zero) }
        }
        let sleeps = Activity<SleepActivityAttributes>.activities
        sleepID = sleeps.first?.id
        for extra in sleeps.dropFirst() {
            let id = extra.id
            Task { await Self.applySleepEnd(id: id) }
        }
    }

    // MARK: Renders

    func updateRender(_ reading: RenderCardReading?, bookTitle: String, coverPath: String?) {
        guard enabled else { return }
        adoptExisting()
        guard let reading else {
            Task { await endRender() }
            return
        }
        let state = RenderActivityAttributes.ContentState(
            headline: reading.headline, detail: reading.detail, ready: reading.ready,
            total: reading.total, fraction: reading.fraction)

        // A card already up for *this* book. `RenderActivityAttributes.bookTitle` is fixed for the
        // life of an activity, so a card that names another book — the reader starting a second
        // book before the first batch finished, or a card adopted from a previous launch — cannot
        // be corrected by an update and has to be replaced (review C3).
        if let renderID, renderBookTitle == bookTitle {
            // `AlertConfiguration`'s title and body are `LocalizedStringResource`, which is
            // `ExpressibleByStringInterpolation` — so an interpolated runtime string compiles,
            // but becomes its own localization key. That is correct here (the text is already
            // composed and there is no catalogue to look it up in); if the compiler objects,
            // the fix is an explicit `LocalizedStringResource(stringLiteral:)`, not a rewrite.
            let alert: AlertConfiguration? = reading.alerts
                ? AlertConfiguration(title: "\(reading.headline)", body: "\(reading.detail)",
                                     sound: .default)
                : nil
            Task {
                let applied = await Self.applyRenderUpdate(
                    id: renderID, content: ActivityContent(state: state, staleDate: nil),
                    alert: alert)
                // Gone from under us — the reader swiped the card away, and ActivityKit ended it.
                // Forget the id: holding on to it meant every later update took this branch,
                // found nothing, returned silently, and no card was ever requested again for the
                // rest of the session (review I3).
                guard applied else {
                    if self.renderID == renderID {
                        self.renderID = nil
                        self.renderBookTitle = nil
                    }
                    return
                }
                // The last thing it will ever say stays up briefly, then clears itself rather
                // than sitting on the Lock Screen for the system's default four hours. Whether
                // this is the last update lives on the reading, not the wire state.
                if reading.isFinished { await endRender(after: .seconds(8)) }
            }
            return
        }

        // Whatever is up names another book. End it now — and clear the id on this turn, before
        // the `Task` runs, so the end below cannot pick up the id of the card requested next.
        if let stale = renderID {
            renderID = nil
            renderBookTitle = nil
            Task { await Self.applyRenderEnd(id: stale, after: .zero) }
        }

        guard !reading.isFinished else { return }
        let attributes = RenderActivityAttributes(bookTitle: bookTitle, coverPath: coverPath)
        renderID = (try? Activity.request(attributes: attributes,
                                          content: ActivityContent(state: state, staleDate: nil),
                                          pushType: nil))?.id
        renderBookTitle = renderID == nil ? nil : bookTitle
    }

    private func endRender(after delay: Duration = .zero) async {
        guard let renderID else { return }
        self.renderID = nil
        self.renderBookTitle = nil
        await Self.applyRenderEnd(id: renderID, after: delay)
    }

    /// Looks the activity back up by `id` from inside a `nonisolated` function, then updates it —
    /// so the value that actually crosses off the main actor is the `String`, not the `Activity`.
    ///
    /// - Returns: false when no activity with that id is running any more, which is the caller's
    ///   cue to forget the id rather than keep addressing a card that is gone.
    private nonisolated static func applyRenderUpdate(
        id: String, content: ActivityContent<RenderActivityAttributes.ContentState>,
        alert: AlertConfiguration?
    ) async -> Bool {
        guard let activity = Activity<RenderActivityAttributes>.activities.first(where: { $0.id == id })
        else { return false }
        await activity.update(content, alertConfiguration: alert)
        return true
    }

    private nonisolated static func applyRenderEnd(id: String, after delay: Duration) async {
        guard let activity = Activity<RenderActivityAttributes>.activities.first(where: { $0.id == id })
        else { return }
        if delay > .zero { try? await Task.sleep(for: delay) }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: Sleep

    func updateSleep(_ reading: SleepCardReading?, bookTitle: String) {
        guard enabled else { return }
        adoptExisting()
        guard let reading else {
            Task { await endSleep() }
            return
        }
        let state = SleepActivityAttributes.ContentState(
            headline: reading.headline, detail: reading.detail, deadline: reading.deadline)
        if let sleepID {
            Task {
                let applied = await Self.applySleepUpdate(
                    id: sleepID, content: ActivityContent(state: state, staleDate: nil))
                // Swiped away: forget it, so the next timer gets a card of its own (review I3).
                if !applied, self.sleepID == sleepID { self.sleepID = nil }
            }
            return
        }
        sleepID = (try? Activity.request(attributes: SleepActivityAttributes(bookTitle: bookTitle),
                                         content: ActivityContent(state: state, staleDate: nil),
                                         pushType: nil))?.id
    }

    private func endSleep() async {
        guard let sleepID else { return }
        self.sleepID = nil
        await Self.applySleepEnd(id: sleepID)
    }

    /// - Returns: false when no activity with that id is running any more.
    private nonisolated static func applySleepUpdate(
        id: String, content: ActivityContent<SleepActivityAttributes.ContentState>
    ) async -> Bool {
        guard let activity = Activity<SleepActivityAttributes>.activities.first(where: { $0.id == id })
        else { return false }
        await activity.update(content)
        return true
    }

    private nonisolated static func applySleepEnd(id: String) async {
        guard let activity = Activity<SleepActivityAttributes>.activities.first(where: { $0.id == id })
        else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    // Deliberately no `endAll()`. It existed, ended both, and was called from nowhere — there is
    // no moment in the app that means "end both at once": a queue that empties ends the render
    // card through `updateRender(nil)`, and a timer that is cancelled ends the sleep card through
    // `updateSleep(nil)`. Code that describes a behaviour the app does not have is worse than no
    // code (review I4).
}
