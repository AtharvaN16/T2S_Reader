import Foundation
import Observation
import T2SAudio
import T2SCore

/// The soundscape's behaviour (soundscape design §4.2): what the bed holds, and how loud it is
/// right now. The bed follows the voice — up while the book plays, down when it pauses — with two
/// exceptions and no third: the audition window after a tap on the picker, and the linger after
/// the sleep timer. Driven by the app's ticker; the clock is injected so tests do not wait.
///
/// Levels are decibels throughout and only become a linear gain at the player's door, so every
/// fade is a straight line the ear hears as even. A swap waits for silence: the old bed is told
/// to fall, the new loop goes in at the floor, and it rises if it is wanted.
@MainActor
@Observable
public final class SoundscapeModel {
    /// The floor: below anything audible, and told to the player as zero.
    public static let silence: Float = -80
    static let auditionSeconds: TimeInterval = 8
    static let lingerSeconds: TimeInterval = 20
    static let fadeSeconds: TimeInterval = 1.5
    static let swapFadeSeconds: TimeInterval = 0.8

    public private(set) var choice: Soundscape?
    /// The slider, 0…1, written through to the preference (which clamps it).
    public var volume: Double {
        didSet {
            preferences.soundscapeVolume = volume
            // `didSet` fires on every assignment, even one that sets the same value again — an
            // unconditional `volume = preferences.soundscapeVolume` here recurses forever. Only
            // write back when the preference actually clamped it.
            let clamped = preferences.soundscapeVolume
            if clamped != volume { volume = clamped }
        }
    }
    /// True while a fade is in flight, for the ticker to tick faster.
    public private(set) var isRamping = false

    private let bed: any BedPlaying
    private let loader: any SoundscapeLoading
    private let preferences: ReaderPreferences
    private let isVoicePlaying: @MainActor () -> Bool
    private let clock: @Sendable () -> Date
    /// What the bed holds now; nil when it holds nothing.
    private var loaded: Soundscape?
    /// A choice waiting for the bed to fall silent before it goes in; a nil soundscape is Off.
    private var pending: (soundscape: Soundscape?, loop: PCMAudio?)?
    private var auditionUntil: Date?
    private var lingerUntil: Date?
    private var ramp: GainRamp?
    /// The level the bed is at, in dB; `silence` when off.
    private var level: Float = SoundscapeModel.silence
    private var generation = 0

    public init(bed: any BedPlaying, loader: any SoundscapeLoading, preferences: ReaderPreferences,
                isVoicePlaying: @escaping @MainActor () -> Bool,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.bed = bed
        self.loader = loader
        self.preferences = preferences
        self.isVoicePlaying = isVoicePlaying
        self.clock = clock
        choice = Soundscape.named(preferences.soundscapeID)
        volume = preferences.soundscapeVolume
        // The remembered choice is loaded on the first tick that wants it, through `choose`'s
        // path, so a launch does not decode a file nobody is listening to yet.
        if let choice { Task { await self.choose(choice, auditioning: false) } }
    }

    /// The bed the reader wants. Persists at once and auditions; the audio follows — the current
    /// bed fades out, the new loop goes in when it is silent, and it rises if it is wanted.
    public func choose(_ soundscape: Soundscape?) async {
        await choose(soundscape, auditioning: true)
    }

    private func choose(_ soundscape: Soundscape?, auditioning: Bool) async {
        preferences.soundscapeID = soundscape?.id
        choice = soundscape
        if auditioning { audition() }
        guard soundscape != loaded || pending != nil else { return }
        generation += 1
        let mine = generation
        let loop: PCMAudio? = if let soundscape { await loader.load(soundscape) } else { nil }
        guard mine == generation else { return }                              // a later choice won
        pending = (soundscape, loop)
        tick()
    }

    /// Eight seconds of the bed whatever the voice is doing: a choice heard where it is made.
    public func audition() {
        auditionUntil = clock().addingTimeInterval(Self.auditionSeconds)
    }

    /// The sleep timer has stopped the voice: take twenty seconds to go, not one and a half.
    public func linger() {
        guard loaded != nil else { return }
        lingerUntil = clock().addingTimeInterval(Self.lingerSeconds)
    }

    public func tick() {
        let now = clock()
        if let pending {
            if level <= Self.silence, ramp == nil {
                bed.setBed(pending.loop)
                loaded = pending.loop == nil ? nil : pending.soundscape
                self.pending = nil
            } else {
                aim(at: Self.silence, over: Self.swapFadeSeconds, now: now)
                advance(now)
                return
            }
        }
        let auditioning = auditionUntil.map { now < $0 } ?? false
        let wanted = loaded != nil && (isVoicePlaying() || auditioning) ? Self.decibels(volume) : Self.silence
        if wanted > Self.silence {
            lingerUntil = nil                                                  // a play cancels the linger
            if level > Self.silence, ramp == nil {
                set(wanted)                                                    // a slider move: at once
            } else {
                aim(at: wanted, over: Self.fadeSeconds, now: now)
            }
        } else if let lingerUntil, now < lingerUntil {
            aim(at: Self.silence, over: lingerUntil.timeIntervalSince(now), now: now)
        } else {
            aim(at: Self.silence, over: Self.fadeSeconds, now: now)
        }
        advance(now)
    }

    /// The slider's position as a level: −36 dB at the bottom, −6 dB at the top, −24 dB at 0.4.
    public static func decibels(_ volume: Double) -> Float {
        -36 + 30 * Float(min(1, max(0, volume)))
    }

    /// Starts a ramp from the current level to `target`, unless one is already headed there.
    private func aim(at target: Float, over seconds: TimeInterval, now: Date) {
        if let ramp, ramp.to == target { return }
        if level == target { ramp = nil; return }
        ramp = GainRamp(from: level, to: target, start: now, duration: seconds)
    }

    /// Moves the level along the ramp and tells the bed.
    private func advance(_ now: Date) {
        guard let ramp else { isRamping = false; return }
        level = ramp.value(at: now)
        if ramp.isDone(at: now) {
            level = ramp.to
            self.ramp = nil
        }
        isRamping = self.ramp != nil
        bed.setBedVolume(level <= Self.silence ? 0 : Loudness.linear(level))
    }

    private func set(_ target: Float) {
        guard level != target else { return }
        level = target
        bed.setBedVolume(Loudness.linear(level))
    }
}
