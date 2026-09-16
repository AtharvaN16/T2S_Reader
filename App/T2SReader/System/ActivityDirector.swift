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
    private var sleepID: String?

    private var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    // MARK: Renders

    func updateRender(_ reading: RenderCardReading?, bookTitle: String, coverPath: String?) {
        guard enabled else { return }
        guard let reading else {
            Task { await endRender() }
            return
        }
        let state = RenderActivityAttributes.ContentState(
            headline: reading.headline, detail: reading.detail, ready: reading.ready,
            total: reading.total, fraction: reading.fraction)

        if let renderID {
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
                await Self.applyRenderUpdate(id: renderID,
                                             content: ActivityContent(state: state, staleDate: nil),
                                             alert: alert)
                // The last thing it will ever say stays up briefly, then clears itself rather
                // than sitting on the Lock Screen for the system's default four hours. Whether
                // this is the last update lives on the reading, not the wire state.
                if reading.isFinished { await endRender(after: .seconds(8)) }
            }
            return
        }

        guard !reading.isFinished else { return }
        let attributes = RenderActivityAttributes(bookTitle: bookTitle, coverPath: coverPath)
        renderID = (try? Activity.request(attributes: attributes,
                                          content: ActivityContent(state: state, staleDate: nil),
                                          pushType: nil))?.id
    }

    private func endRender(after delay: Duration = .zero) async {
        guard let renderID else { return }
        self.renderID = nil
        await Self.applyRenderEnd(id: renderID, after: delay)
    }

    /// Looks the activity back up by `id` from inside a `nonisolated` function, then updates it —
    /// so the value that actually crosses off the main actor is the `String`, not the `Activity`.
    private nonisolated static func applyRenderUpdate(
        id: String, content: ActivityContent<RenderActivityAttributes.ContentState>,
        alert: AlertConfiguration?
    ) async {
        guard let activity = Activity<RenderActivityAttributes>.activities.first(where: { $0.id == id })
        else { return }
        await activity.update(content, alertConfiguration: alert)
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
        guard let reading else {
            Task { await endSleep() }
            return
        }
        let state = SleepActivityAttributes.ContentState(
            headline: reading.headline, detail: reading.detail, deadline: reading.deadline)
        if let sleepID {
            Task {
                await Self.applySleepUpdate(id: sleepID, content: ActivityContent(state: state, staleDate: nil))
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

    private nonisolated static func applySleepUpdate(
        id: String, content: ActivityContent<SleepActivityAttributes.ContentState>
    ) async {
        guard let activity = Activity<SleepActivityAttributes>.activities.first(where: { $0.id == id })
        else { return }
        await activity.update(content)
    }

    private nonisolated static func applySleepEnd(id: String) async {
        guard let activity = Activity<SleepActivityAttributes>.activities.first(where: { $0.id == id })
        else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: Teardown

    func endAll() {
        Task {
            await endRender()
            await endSleep()
        }
    }
}
