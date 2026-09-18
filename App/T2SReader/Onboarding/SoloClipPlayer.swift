// App/T2SReader/Onboarding/SoloClipPlayer.swift
import AVFoundation
import Foundation
import Observation

/// One clip played whole at the reader's request — the passage, in the voice the reader is trying.
/// `isPlaying` is true from `play()` until the clip ends or `stop()`.
///
/// This file used to hold a second player as well: `ClipPlayer`, one `AVAudioPlayer` per rising
/// cover, whose volumes a schedule moved so a few opening lines chattered past one another over
/// the reel. The owner took the voice off the reel on 2026-09-18 ("remove the voice from the
/// onboarding video"), and with it that player, `ChatterSchedule`, and the reel's dependence on
/// how long a set of clips happened to run. The per-book `line` clips in the bundle are unused by
/// the app now; only the hero's `passage` clips are played, and only here.
@MainActor
@Observable
final class SoloClipPlayer: NSObject, AVAudioPlayerDelegate {
    /// `T2S_SILENT=1` mutes every player, as it mutes `AudioPlayer`: the simulator screenshot
    /// recipe runs on the owner's Mac, whose speakers are never to be used.
    static let isSilent = ProcessInfo.processInfo.environment["T2S_SILENT"].map { $0 != "0" && !$0.isEmpty } ?? false

    private var player: AVAudioPlayer?
    private(set) var isPlaying = false
    /// True from the first `play()` on, so "heard through" is `hasPlayed && !isPlaying`.
    private(set) var hasPlayed = false

    /// The clip's position, for a tint that follows the voice.
    var currentTime: TimeInterval { player?.currentTime ?? 0 }

    func play(_ url: URL?) {
        stop()
        hasPlayed = true
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.volume = Self.isSilent ? 0 : 1
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
