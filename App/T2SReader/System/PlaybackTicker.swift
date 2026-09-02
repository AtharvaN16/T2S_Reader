// App/T2SReader/System/PlaybackTicker.swift
import SwiftUI
import T2SApp

/// Spec §3: the coordinator polls the player clock. One 10 Hz loop for the whole app, alive while
/// the root view is; it only calls `tick()` while something is playing.
private struct PlaybackTicking: ViewModifier {
    let player: PlayerModel

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                if player.isPlaying { player.tick() }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

extension View {
    func playbackTicking(_ player: PlayerModel) -> some View { modifier(PlaybackTicking(player: player)) }
}
