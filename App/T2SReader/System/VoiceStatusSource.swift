// App/T2SReader/System/VoiceStatusSource.swift
import Foundation
import SwiftUI
import T2SApp

/// The one-time voice warm-up, as a client of the status band.
///
/// Everything here was `WarmUpLine`'s, and it is the only part of the warm-up that knows about
/// `KokoroStatus`. Moving it off the view is the point: a second job — a render queue, an import —
/// now writes one of these and says nothing at all about drawing.
@MainActor
final class VoiceStatusSource: StatusSource {
    let kind: StatusKind = .voice
    private let status: KokoroStatusModel
    private let player: PlayerModel
    /// The slot this source speaks in, held `unowned` because the model owns the graph that owns
    /// this source: `AppEnvironment` builds both and outlives both, so a strong reference here
    /// would be a cycle and a weak one would be an optional that is never nil.
    private unowned let appStatus: AppStatusModel

    init(status: KokoroStatusModel, player: PlayerModel, appStatus: AppStatusModel) {
        self.status = status
        self.player = player
        self.appStatus = appStatus
    }

    /// Warming, or holding the beat that ends a warm-up. Nothing about playback: what the reader
    /// is listening to while the stages load is not what decides whether the wait is on screen.
    ///
    /// **The gate is the whole of the rule, and it is the whole of it on purpose.** The glow used
    /// to hide the moment audio flowed from the phone's own voice — a book playing with a pulse
    /// over it read as an alarm rather than a wait (owner, 2026-09-10) — with the hosted voice
    /// carved out as an exception a fortnight later (owner, 2026-09-12: Heart from the mirrors
    /// *is* the wait for Heart on the phone). The carve-out was the tell. A reader who has started
    /// a book is precisely the one who wants to know how much longer the on-device voice will be,
    /// and taking the light and the bar away on the first sound left them reading in the system
    /// voice with nothing on screen to say a download was still running (owner, 2026-09-13: "I
    /// need to be aware of the status"). So the rule is the plain one: the wait shows for as long
    /// as the wait lasts, whichever voice is speaking over it. Every clause this used to carry
    /// existed to punch a hole back through a playback gate that is gone — do not add one back.
    ///
    /// The alarm the old rule was avoiding is answered by the words rather than by hiding the
    /// light: the band names the phase, so a breathing rim over a book that is reading aloud is
    /// captioned "Downloading the voice" and not left to be guessed at.
    /// Whether the wait wants the band on screen: warming, or holding the beat that ends a
    /// warm-up. Going false is what starts the fade.
    var isActive: Bool { status.status.isWarming || status.isHoldingReadyBeat }

    func reading(now: Date) -> StatusReading? {
        // Deliberately a wider gate than ``isActive``, and the two part company for exactly one
        // fade. `readyAt` outlives the beat it dates — the status model stopped clearing it on
        // 2026-09-12 for this reason — so once a warm-up has ended this keeps returning the
        // ending: "Voice ready", the bar full, the tone the rims are crossing to. That is what
        // the reader watches leave. Answering nil here the moment `isActive` dropped blanked the
        // words on the first frame of a 1.5 s fade and left two lit rims over nothing.
        //
        // After the fade the band is at zero opacity and this is still answering, which costs a
        // struct a frame and is exactly what the old `WarmUpLine` did — it resolved forever too,
        // and was simply not on screen.
        guard isActive || status.readyAt != nil else { return nil }
        // The beat is one date, so the rims and the rows turn on the same frame.
        if status.readyAt != appStatus.endedAt { appStatus.markEnding(at: status.readyAt) }
        return WarmUpReading(phase: phase(now: now),
                             progress: progress(now: now),
                             afterAnInstall: status.launchIncludedInstall).reading
    }

    /// Whether the hosted voice is the one speaking through this wait.
    private var isHostedSpeaking: Bool { player.routedVoiceID?.hasPrefix("cloud:") == true }

    // MARK: what the status means

    /// Maps this launch's state onto the phase `WarmUpReading` answers about. The mapping is the
    /// only part of the line that knows about `KokoroStatus`.
    private func phase(now: Date) -> WarmUpReading.Phase {
        if status.readyAt != nil {
            guard !status.endedFailed else {
                return .failed(status.endedFailedDuringInstall ? .install : .warmUp)
            }
            return .ready(buildingBackgroundSet: status.isBuildingBackgroundSet)
        }
        if case .installing = status.status { return installPhase(now: now) }
        // Heart from the mirrors is speaking while Heart installs on the phone. The glow stays up
        // through that audio on purpose, and this is the only line that explains why it is there.
        if isHostedSpeaking {
            return .hostedVoiceSpeaking(secondsLeft: secondsLeft(now: now))
        }
        if case .checking = status.status { return .checking }
        let left = secondsLeft(now: now)
        return .warming(secondsLeft: left, stalled: isStalled(now: now))
    }

    private func installPhase(now: Date) -> WarmUpReading.Phase {
        switch status.installProgress {
        case .none:
            // The split second after the install begins and before its first callback: nothing has
            // been counted yet, so there is nothing to count with.
            return .waitingForNetwork
        case .waitingForNetwork:
            return .waitingForNetwork
        case .downloading(let bytes, let total):
            return .downloading(received: megabytes(bytes), total: megabytes(total))
        case .retrying(_, _, let after, _):
            // `after` is the delay the retry was scheduled with, so on its own it never counts down
            // — the line read "trying again in 7 s" for the whole seven seconds. Subtracting the
            // time since the model took it makes it tick.
            let left = after - now.timeIntervalSince(status.installProgressAt)
            return .retrying(secondsLeft: Int(max(0, left).rounded(.up)))
        case .compiling(let stage, let total):
            return .preparing(step: stage, of: total, secondsLeft: nil)
        }
    }

    /// The clock: what is left of the length this phone remembered. Nil before there is one to
    /// remember, once it is spent, and while the warm-up has not started counting.
    private func secondsLeft(now: Date) -> Int? {
        guard let expected = status.expectedWarmUpSeconds, let started = status.warmUpStarted else { return nil }
        let left = expected - now.timeIntervalSince(started)
        guard left > 1 else { return nil }
        // Rounded up to the next five above ten seconds, so it does not tick every second for
        // minutes; below that it counts honestly, because a reader is watching the last few.
        return left < 10 ? Int(left.rounded(.up)) : Int((left / 5).rounded(.up)) * 5
    }

    /// Well past what this phone remembered, the estimate has stopped being a fact about anything.
    /// The title admits it and the clock goes, rather than freezing on a number that went wrong.
    private func isStalled(now: Date) -> Bool {
        guard let expected = status.expectedWarmUpSeconds, let started = status.warmUpStarted else { return false }
        return now.timeIntervalSince(started) > expected * 2
    }

    /// The floor and the clock's own guess, whichever is further on. Stages are exact but coarse and
    /// the clock is smooth but a guess; the floor is what keeps either of them from retreating at
    /// the install-to-stages seam or on a retried stage load.
    private func progress(now: Date) -> Double {
        if status.readyAt != nil { return status.endedFailed ? status.warmUpProgressFloor : 1 }
        guard let expected = status.expectedWarmUpSeconds, let started = status.warmUpStarted else {
            return status.warmUpProgressFloor
        }
        let byClock = min(0.92, now.timeIntervalSince(started) / max(1, expected))
        let scaled = status.launchIncludedInstall
            ? KokoroStatusModel.installShare + (1 - KokoroStatusModel.installShare) * byClock
            : byClock
        return max(status.warmUpProgressFloor, scaled)
    }

    private func megabytes(_ bytes: Int) -> Int { Int((Double(bytes) / 1_000_000).rounded()) }
}
