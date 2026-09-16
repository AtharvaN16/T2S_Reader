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
/// Nothing here decides *what* the card says. That is `RenderCardReading` and
/// `SleepCardReading`, which are plain values and are tested.
@MainActor
final class ActivityDirector {
    private var render: Activity<RenderActivityAttributes>?
    private var sleep: Activity<SleepActivityAttributes>?

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

        if let render {
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
                await render.update(ActivityContent(state: state, staleDate: nil), alertConfiguration: alert)
                // The last thing it will ever say stays up briefly, then clears itself rather
                // than sitting on the Lock Screen for the system's default four hours. Whether
                // this is the last update lives on the reading, not the wire state.
                if reading.isFinished { await endRender(after: .seconds(8)) }
            }
            return
        }

        guard !reading.isFinished else { return }
        let attributes = RenderActivityAttributes(bookTitle: bookTitle, coverPath: coverPath)
        render = try? Activity.request(attributes: attributes,
                                       content: ActivityContent(state: state, staleDate: nil),
                                       pushType: nil)
    }

    private func endRender(after delay: Duration = .zero) async {
        guard let render else { return }
        self.render = nil
        if delay > .zero { try? await Task.sleep(for: delay) }
        await render.end(nil, dismissalPolicy: .immediate)
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
        if let sleep {
            Task { await sleep.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        sleep = try? Activity.request(attributes: SleepActivityAttributes(bookTitle: bookTitle),
                                      content: ActivityContent(state: state, staleDate: nil),
                                      pushType: nil)
    }

    private func endSleep() async {
        guard let sleep else { return }
        self.sleep = nil
        await sleep.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: Teardown

    func endAll() {
        Task {
            await endRender()
            await endSleep()
        }
    }
}
