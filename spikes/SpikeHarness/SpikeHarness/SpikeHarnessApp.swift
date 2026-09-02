import SwiftUI
import MLX

@main
struct SpikeHarnessApp: App {
    init() {
        // Same limits KokoroTestApp uses; MLX otherwise grows its cache without bound.
        GPU.set(cacheLimit: 50 * 1024 * 1024)
        GPU.set(memoryLimit: 900 * 1024 * 1024)
        UIDevice.current.isBatteryMonitoringEnabled = true
        SpikeLog.shared.record("app.launch", [
            "device": UIDevice.current.model,
            "system": UIDevice.current.systemVersion,
        ])
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
