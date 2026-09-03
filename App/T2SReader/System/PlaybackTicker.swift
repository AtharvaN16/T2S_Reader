// App/T2SReader/System/PlaybackTicker.swift
import SwiftUI
import T2SApp

/// Spec §3: the coordinator polls the player clock. One loop for the whole app, alive while the
/// root view is. 10 Hz while something is playing, 1 Hz otherwise, so an idle app is not woken ten
/// times a second. It deliberately does *not* stop on scene phase: background listening (spec §3.6)
/// still needs the ticks, because the coordinator schedules from them.
private struct PlaybackTicking: ViewModifier {
    let player: PlayerModel

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                let playing = player.isPlaying
                if playing { player.tick() }
                try? await Task.sleep(for: playing ? .milliseconds(100) : .seconds(1))
            }
        }
    }
}

extension View {
    func playbackTicking(_ player: PlayerModel) -> some View { modifier(PlaybackTicking(player: player)) }
}
