import Foundation

/// How loud the voice looks, for the glow at the crown of the welcome's page (design:
/// `docs/superpowers/specs/2026-09-16-onboarding-reel-welcome-page-design.md`; the owner,
/// 2026-09-16: "a glowing element which reacts to the voice").
///
/// Derived from the clip's word timings rather than from the player, deliberately.
/// `AVAudioPlayer`'s metering reports the player's *output*, which `T2S_SILENT=1` pins at zero —
/// so a glow driven by it would be dead in every frame the simulator recipe photographs (see
/// `ClipPlayer.isSilent`, and the owner's Mac never plays sound). The timings ship beside every
/// clip and are what the read-along already reads, so the level costs nothing extra, is the same
/// on every run, and is a plain function of time that tests without an audio session.
///
/// Each word is an attack and a decay: the level jumps to full over `attack` at the word's onset
/// and falls back towards `floor` over the rest of it, so the glow pulses once per word and
/// breathes in the gaps between them rather than flickering per syllable.
public struct VoiceEnvelope: Hashable, Sendable {
    /// Word onsets and ends, in play order.
    public var words: [(start: TimeInterval, end: TimeInterval)]

    /// How long the rise to full takes. Short — a word's attack is the consonant, not the vowel.
    public static let attack: TimeInterval = 0.06
    /// The level between words: never dark, so the glow reads as a voice at rest rather than as
    /// something that has been switched off.
    public static let floor: Double = 0.22
    /// The longest a word's decay runs, however long the word is held: a word drawn out over a
    /// second should not leave the glow at full for all of it.
    public static let decay: TimeInterval = 0.42

    public init(words: [(start: TimeInterval, end: TimeInterval)]) {
        self.words = words
    }

    public init(timings: OnboardingClipTimings?) {
        self.init(words: (timings?.words ?? []).map { ($0.start, $0.end) })
    }

    public static func == (a: VoiceEnvelope, b: VoiceEnvelope) -> Bool {
        a.words.count == b.words.count
            && zip(a.words, b.words).allSatisfy { $0.start == $1.start && $0.end == $1.end }
    }

    public func hash(into hasher: inout Hasher) {
        for word in words { hasher.combine(word.start); hasher.combine(word.end) }
    }

    /// The level at `time`, `floor`…1. Before the first word and after the last, the floor: the
    /// glow is lit and still, waiting.
    public func level(at time: TimeInterval) -> Double {
        guard let word = word(at: time) else { return Self.floor }
        let since = time - word.start
        guard since >= 0 else { return Self.floor }
        if since < Self.attack {
            return Self.floor + (1 - Self.floor) * (since / Self.attack)
        }
        // Over the word's own length or `decay`, whichever is shorter, so a long held word does
        // not hold the glow up with it.
        let span = max(min(word.end - word.start - Self.attack, Self.decay), 0.001)
        let t = min((since - Self.attack) / span, 1)
        return Self.floor + (1 - Self.floor) * (1 - t * t)
    }

    /// The word sounding at `time`: the last one to have started, and only while it still runs.
    /// Nil before the first word and in any gap after one has ended, so silence falls to the floor
    /// rather than holding the last word's decay.
    private func word(at time: TimeInterval) -> (start: TimeInterval, end: TimeInterval)? {
        var found: (start: TimeInterval, end: TimeInterval)?
        for word in words where word.start <= time { found = word }
        guard let found, time < found.end else { return nil }
        return found
    }
}
