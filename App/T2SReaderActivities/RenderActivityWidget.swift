import ActivityKit
import SwiftUI
import WidgetKit

/// The render queue, on the Lock Screen and in the real Dynamic Island.
///
/// The Lock Screen has room for the bar the mock island deliberately has not got — which is the
/// whole division of labour: in the app the Book sheet's progress box already shows the work, so
/// the capsule only announces the finish; out of the app nothing else is telling anyone
/// anything, so this carries the count and the bar.
struct RenderActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RenderActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(context.state.headline).font(.headline)
                Text(context.state.detail).font(.subheadline).foregroundStyle(.secondary)
                ProgressView(value: context.state.fraction).tint(.primary)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.7))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform").font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.ready)/\(context.state.total)")
                        .font(.title3).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.headline).font(.headline)
                        ProgressView(value: context.state.fraction).tint(.white)
                    }
                }
            } compactLeading: {
                Image(systemName: "waveform")
            } compactTrailing: {
                Text("\(context.state.ready)/\(context.state.total)").monospacedDigit()
            } minimal: {
                Image(systemName: "waveform")
            }
        }
    }
}
