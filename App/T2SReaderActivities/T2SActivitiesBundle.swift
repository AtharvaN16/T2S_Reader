import SwiftUI
import WidgetKit

@main
struct T2SActivitiesBundle: WidgetBundle {
    var body: some Widget {
        RenderActivityWidget()
        SleepActivityWidget()
    }
}
