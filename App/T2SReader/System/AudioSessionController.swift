// App/T2SReader/System/AudioSessionController.swift
import AVFoundation
import Foundation
import os

/// Spec §3.5. Activates the spoken-audio playback session, pauses on interruptions (a call,
/// another app taking the output) and when headphones are unplugged, and — the half that keeps
/// playback alive — reactivates the session when the interruption ends, resuming only what the
/// interruption itself stopped.
@MainActor
final class AudioSessionController {
    private static let log = Logger(subsystem: "com.t2s.reader", category: "audio")
    private var observers: [NSObjectProtocol] = []
    /// `.onAppear` can fire more than once for a `WindowGroup`'s root; registering twice would
    /// deliver every notification twice.
    private var started = false
    /// Set when an interruption paused us, so `.ended` resumes only after an interruption.
    private var pausedByInterruption = false

    /// `pausing` returns whether playback was active when it paused; only that pause is undone by
    /// a `.shouldResume` ending — a book the listener paused themselves stays paused.
    func activate(pausing pause: @escaping @MainActor () -> Bool, resuming resume: @escaping @MainActor () -> Void) {
        guard !started else { return }
        started = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            // Playback still works through the default session; the loss is background continuation.
            Self.log.error("Audio session activation failed: \(error.localizedDescription, privacy: .public)")
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                MainActor.assumeIsolated { self.interruptionBegan(pause) }
            } else if raw == AVAudioSession.InterruptionType.ended.rawValue {
                MainActor.assumeIsolated { self.interruptionEnded(options: optionsRaw, resume: resume) }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { MainActor.assumeIsolated { _ = pause() } }
        })
    }

    /// `pause()` is idempotent, so it runs unconditionally; it reports whether it actually stopped
    /// playback, and only then does `.shouldResume` on the matching `.ended` resume anything.
    private func interruptionBegan(_ pause: @MainActor () -> Bool) {
        pausedByInterruption = pause()
    }

    /// The session is deactivated for us during an interruption: without this `setActive(true)`
    /// nothing plays again for the life of the process.
    private func interruptionEnded(options optionsRaw: UInt, resume: @MainActor () -> Void) {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Self.log.error("Audio session reactivation failed: \(error.localizedDescription, privacy: .public)")
        }
        if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume), pausedByInterruption { resume() }
        pausedByInterruption = false
    }
}
