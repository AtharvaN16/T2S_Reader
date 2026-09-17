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
                        // The status band, in a window one level above this one, for the life of
                        // the app. Here rather than in a scene delegate: this is the first moment
                        // the scene is certainly connected and the environment certainly exists,
                        // and it costs the app no `UIApplicationDelegateAdaptor` it does not
                        // otherwise have. `attach` is idempotent — this closure can run again.
                        StatusBandHost.attach(to: environment)
                        // The capsule, one level above the band's window. Same reason the band
                        // has one — it must be over the Reader's full-screen cover — but this
                        // one answers touches inside itself, because it carries a Play button.
                        MockIslandHost.attach(to: environment)
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
                        // Wait for the Kokoro install and warm-up first, however long they take. The
                        // prime's own first `synthesize` would otherwise block on the engine's load
                        // while holding the shared render lease, so a system- or cloud-voice document
                        // tapped during the warm-up would wait for a model it does not use — and a
                        // prime that ran on a deadline would build compute plans in the background
                        // if the phone had locked meanwhile, which is what iOS kills a process for.
                        // `.notLinked`, `.available` and `.unavailable` never wait.
                        while !Task.isCancelled, environment.kokoroStatus.status.isWarming {
                            try? await Task.sleep(for: .milliseconds(250))
                        }
                        guard !Task.isCancelled else { return }
                        await environment.foregroundGate.waitUntilForeground()
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
