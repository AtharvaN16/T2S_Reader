// App/T2SReader/System/AudioSessionController.swift
import AVFoundation
import Foundation

/// Spec §3.5. Activates the spoken-audio playback session and pauses on interruptions (a call,
/// another app taking the output) and when headphones are unplugged.
@MainActor
final class AudioSessionController {
    private var observers: [NSObjectProtocol] = []

    func activate(pausing pause: @escaping @MainActor () -> Void) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            // Playback still works through the default session; the loss is background continuation.
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue { MainActor.assumeIsolated { pause() } }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { MainActor.assumeIsolated { pause() } }
        })
    }
}
