// App/T2SReader/System/PlaybackTicker.swift
import SwiftUI
import T2SApp

/// Spec §3: the coordinator polls the player clock. One loop for the whole app, alive while the
/// root view is. 10 Hz while something is playing, 1 Hz otherwise, so an idle app is not woken ten
/// times a second. It deliberately does *not* stop on scene phase: background listening (spec §3.6)
/// still needs the ticks, because the coordinator schedules from them.
private struct PlaybackTicking: ViewModifier {
    let player: PlayerModel
    let sleepTimer: SleepTimer
    let continuation: QueueContinuation
    @State private var handledFinish = false

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                let playing = player.isPlaying
                if playing { player.tick() }
                sleepTimer.tick()
                if player.state == .finished {
                    if !handledFinish {
                        handledFinish = true
                        _ = await continuation.advanceIfFinished()
                    }
                } else {
                    handledFinish = false
                }
                try? await Task.sleep(for: .milliseconds(playing ? 100 : 250))
            }
        }
    }
}

extension View {
    func playbackTicking(_ player: PlayerModel, sleepTimer: SleepTimer, continuation: QueueContinuation) -> some View {
        modifier(PlaybackTicking(player: player, sleepTimer: sleepTimer, continuation: continuation))
    }
}
