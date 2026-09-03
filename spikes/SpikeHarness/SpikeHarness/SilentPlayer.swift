// SilentPlayer.swift — Plan 0 Task 2 (§7.2): keeps an `audio` background session alive with a
// looping silent buffer so the bench can run with the screen locked.
import AVFoundation

final class SilentPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24_000)!
        silence.frameLength = 24_000
        player.scheduleBuffer(silence, at: nil, options: .loops)
        player.play()
    }
}
