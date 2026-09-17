// App/T2SReader/Onboarding/VoiceGlow.swift
import SwiftUI
import T2SApp

/// The light at the crown of the welcome's page: the warm-up's own rim, in the chosen voice's
/// colour, breathing with the words (design:
/// `docs/superpowers/specs/2026-09-16-onboarding-reel-welcome-page-design.md`; the owner,
/// 2026-09-17: "the glow should be similar to the rim glow on warmup, but only on top").
///
/// **It is literally that glow.** `StatusRamp.wash` and `StatusRamp.bezel` are what the voice
/// warm-up paints — a faint wash under the top edge and one stroke of light along the screen's
/// edge, round the corners at the real display radius and a little way down the sides — and this
/// passes them a voice's colour and a pulse of its own instead of the warm-up's blue and its
/// three-second breath. Reusing them rather than making a second kind of light means the app has
/// one glow with two drivers: when the bezel radius or the halo's reach is next tuned, both move.
///
/// Only the top edge. `StatusRim` can face either way and flips itself for the foot; here there is
/// nothing at the foot but the key and its fade.
///
/// **Dithered, for the same reason the warm-up is.** These are very shallow gradients and 8 bits
/// cannot hold them: a ramp like this holds one value for ten or twenty rows and then steps, and
/// the eye reads every step as a line across the screen. The owner saw exactly that band under the
/// voice row on 2026-09-17. `StatusRamp.ditherTile` scatters each step's edge into a pattern too
/// fine to see, masked to the glow's own alpha so it never lands as grain on bare ground.
///
/// An earlier cut gave each voice a *form* as well as a colour — an orb, a band, two lobes, a
/// ring, a core. That is gone with the rim: the rim is one shape, and what a voice changes is the
/// colour it is lit in.
struct VoiceGlow: View {
    var voice: String
    var voices: [String]
    /// `VoiceEnvelope.floor`…1, once a frame.
    var level: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The quietest the light gets between words. Well clear of nothing: the warm-up may breathe
    /// almost out because it is telling you to wait, where this is telling you who is reading, and
    /// a rim that keeps vanishing reads as a fault.
    static let floor: Double = 0.42

    var body: some View {
        let light = VoicePalette.glow(for: voice, in: voices)
        let glow = ZStack {
            StatusRamp.wash(pulse: pulse, light: light)
            StatusRamp.bezel(pulse: pulse, light: light)
        }
        return glow
            .overlay {
                StatusRamp.ditherTile
                    .resizable(resizingMode: .tile)
                    .blendMode(.overlay)
                    .opacity(0.3)
                    .mask(glow)
            }
            .frame(height: StatusRamp.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // No animation on the pulse: the scene is already inside a `TimelineView(.animation)`,
            // so this redraws every frame anyway, and hanging an implicit animation off a value
            // that changes every frame is what made the Reader's scrubber stutter. Only the change
            // of voice animates, because that is a step between two colours rather than a value in
            // motion.
            .animation(.smooth(duration: 0.45), value: voice)
    }

    /// The envelope's level as the rim's breath. `VoiceEnvelope` sits at its own floor between
    /// words — which is most of any frame — so the level is stretched off that floor rather than
    /// used raw: mapped straight through, the light would be at a fifth of its strength almost
    /// always and would barely register.
    private var pulse: Double {
        guard !reduceMotion else { return 0.8 }
        let range = max(1 - VoiceEnvelope.floor, 0.001)
        let lifted = min(max((level - VoiceEnvelope.floor) / range, 0), 1)
        return Self.floor + (1 - Self.floor) * lifted
    }
}

/// One colour per voice, shared by the pill and the light above it so the two never disagree —
/// they are the same statement made twice, and a pill in one hue under a rim in another reads as a
/// bug.
///
/// Spaced around the wheel by the voice's place in the row so neighbours never look alike, which
/// scales to any number of voices: a book added to the manifest adds a voice here too.
enum VoicePalette {
    static func hue(for voice: String, in voices: [String]) -> Double {
        let index = voices.firstIndex(of: voice) ?? 0
        return (Double(index) / Double(max(voices.count, 1)) + 0.02).truncatingRemainder(dividingBy: 1)
    }

    /// The pill's fill: deep enough to carry `onAccent` white across it.
    static func colour(for voice: String, in voices: [String]) -> Color {
        Color(hue: hue(for: voice, in: voices), saturation: 0.66, brightness: 0.64)
    }

    /// The rim's, which is the same hue and nothing else the same. The pill's brightness is pitched
    /// for white text standing on it; as light on the edge of the screen it came out a brown stain
    /// rather than a glow.
    static func glow(for voice: String, in voices: [String]) -> Color {
        Color(hue: hue(for: voice, in: voices), saturation: 0.78, brightness: 0.96)
    }

    /// `af_heart` → `Heart`.
    static func displayName(_ voice: String) -> String {
        let stem = voice.split(separator: "_").last.map(String.init) ?? voice
        return stem.prefix(1).uppercased() + stem.dropFirst()
    }
}
