import ActivityKit
import SwiftUI
import WidgetKit

/// The sleep timer.
///
/// `Text(timerInterval:)` counts down from the stored date **without the app updating it**, so
/// this card costs nothing to keep current — no wake-ups, no update budget, no battery. An
/// `.endOfChapter` sleep has no date and shows its sentence instead, because a clock ticking
/// toward a moment nobody can name would be a lie.
struct SleepActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.headline).font(.headline)
                    countdown(context.state)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.7))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "moon.zzz.fill").font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state).font(.title3)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.bookTitle).font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "moon.zzz.fill")
            } compactTrailing: {
                countdown(context.state)
            } minimal: {
                Image(systemName: "moon.zzz.fill")
            }
        }
    }

    @ViewBuilder
    private func countdown(_ state: SleepActivityAttributes.ContentState) -> some View {
        if let deadline = state.deadline {
            // Clamped, because `Date.now...deadline` *traps* once the deadline is in the past —
            // "Range requires lowerBound <= upperBound" — and nothing guarantees the activity was
            // ended in time. `SleepTimer.tick` runs from the app's ticker, which stops being
            // serviced the moment iOS suspends the app, and a paused-and-pocketed app with a live
            // sleep timer is exactly what this card is for. The extension re-renders on unlock and
            // would crash there (review I5). Settled, it reads 0:00, which is the truth.
            Text(timerInterval: min(Date.now, deadline)...deadline, countsDown: true)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text(state.detail).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
