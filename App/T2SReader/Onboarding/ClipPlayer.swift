// App/T2SReader/Onboarding/ClipPlayer.swift
import AVFoundation
import Foundation
import Observation

/// The welcome's chatter: one `AVAudioPlayer` per rising card, started as its card enters and
/// held at whatever volume `RisingChoreography` says for the card's position, so the lines overlap
/// and bleed into one another as the cards pass, and a line is cut by its fade rather than played
/// out. The clock is the scene's, not the audio's: `update(gains:)` is called once a frame with
/// the choreography's gains, and this only starts, sets and stops players.
///
/// A clip missing from the bundle — before `scripts/render-onboarding-clips.sh` has run — is a
/// silent slot; the scene runs the same without it. `T2S_SILENT=1` mutes every player, as it mutes
/// `AudioPlayer`: the simulator screenshot recipe runs on the owner's Mac, whose speakers are never
/// to be used.
@MainActor
@Observable
final class ClipPlayer {
    private let players: [AVAudioPlayer?]
    private var started: Set<Int> = []

    static let isSilent = ProcessInfo.processInfo.environment["T2S_SILENT"].map { $0 != "0" && !$0.isEmpty } ?? false

    init(urls: [URL?]) {
        players = urls.map { url in
            guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
            player.prepareToPlay()
            return player
        }
    }

    /// Once a frame: a card with a gain starts its voice if it has not, every voice takes its
    /// gain, and a voice whose card has faded out is stopped for good.
    func update(gains: [Float]) {
        for (index, gain) in gains.enumerated() where index < players.count {
            guard let player = players[index] else { continue }
            if gain > 0 {
                if !started.contains(index) {
                    started.insert(index)
                    player.currentTime = 0
                    player.play()
                }
                player.volume = Self.isSilent ? 0 : gain
            } else if started.contains(index), player.isPlaying {
                player.stop()
            }
        }
    }

    func stop() {
        for player in players { player?.stop() }
    }
}

/// One clip played whole at the reader's request — the hero's lines after Play. `isPlaying` is
/// true from `play()` until the clip ends or `stop()`.
@MainActor
@Observable
final class SoloClipPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private(set) var isPlaying = false

    /// The clip's position, for a tint that follows the voice.
    var currentTime: TimeInterval { player?.currentTime ?? 0 }

    func play(_ url: URL?) {
        stop()
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.volume = ClipPlayer.isSilent ? 0 : 1
        player.prepareToPlay()
        self.player = player
        isPlaying = player.play()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
