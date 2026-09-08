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
                    .task {
                        // The continue-document's next 30 s, from where the reader left it, so the
                        // mini-player's first tap after a launch is instant (spec §3.4.1 tier 2).
                        // Here and not in `AppEnvironment.init`: the background Prepare task builds an
                        // environment too, and a prime there would race the prepare for the one slot.
                        //
                        // Wait for the Kokoro warm-up first. The prime's own first `synthesize` would
                        // otherwise block on the engine's load while holding the shared render lease,
                        // so a system- or cloud-voice document tapped during the warm-up would wait
                        // for a model it does not use. The A13's first launch builds compute plans for
                        // ~206 s; five minutes is the bound, and then the prime runs anyway rather
                        // than being lost. `.notLinked`, `.available` and `.unavailable` never wait.
                        let deadline = Date().addingTimeInterval(5 * 60)
                        while Date() < deadline, !Task.isCancelled {
                            let isWarmingUp: Bool
                            switch environment.kokoroStatus.status {
                            case .checking, .preparing: isWarmingUp = true
                            case .notLinked, .available, .unavailable: isWarmingUp = false
                            }
                            guard isWarmingUp else { break }
                            try? await Task.sleep(for: .milliseconds(250))
                        }
                        _ = await environment.prepareRunner.primeContinueDocument()
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
