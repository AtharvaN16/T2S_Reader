// App/T2SReader/T2SReaderApp.swift
import SwiftUI

@main
struct T2SReaderApp: App {
    @State private var environment: AppEnvironment? = {
        do { return try AppEnvironment.live() } catch { return nil }
    }()

    var body: some Scene {
        WindowGroup {
            if let environment {
                RootPager()
                    .environment(environment)
                    .onOpenURL { url in
                        Task { await environment.importModel.importFiles([url]) }
                    }
                    .onAppear {
                        environment.audioSession.activate(pausing: { environment.coordinator.pause() })
                        environment.deviceMonitor.start()
                    }
            } else {
                Text("The library could not be opened.")
                    .typeRole(.rowTitle)
                    .foregroundStyle(Tokens.destructive)
                    .padding(Spacing.margin)
            }
        }
    }
}
