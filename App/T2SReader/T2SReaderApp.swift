// App/T2SReader/T2SReaderApp.swift
import os
import SwiftUI

@main
struct T2SReaderApp: App {
    @State private var environment: AppEnvironment? = {
        do {
            return try AppEnvironment.live()
        } catch {
            // The user only sees "The library could not be opened."; the reason has to go somewhere.
            Logger(subsystem: "com.t2s.reader", category: "launch")
                .error("AppEnvironment.live() failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    init() {
        PrepareTask.register()
    }

    var body: some Scene {
        WindowGroup {
            if let environment {
                RootPager()
                    .environment(environment)
                    .onAppear {
                        environment.audioSession.activate(pausing: {
                                                              let wasPlaying = environment.coordinator.state == .playing || environment.coordinator.state == .catchingUp
                                                              environment.coordinator.pause()
                                                              return wasPlaying
                                                          },
                                                          resuming: { Task { await environment.coordinator.play() } },
                                                          recovering: { Task { await environment.coordinator.recoverAfterMediaServicesReset() } })
                        environment.nowPlaying.start()
                        environment.deviceMonitor.start()
                        PrepareTask.schedule()
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
