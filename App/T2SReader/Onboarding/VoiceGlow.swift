// App/T2SReader/Onboarding/VoiceGlow.swift
import SwiftUI
import T2SApp

/// The light at the crown of the welcome's page: a bloom in the chosen voice's colour that
/// breathes with the words (design:
/// `docs/superpowers/specs/2026-09-16-onboarding-reel-welcome-page-design.md`; the owner,
/// 2026-09-16: "the top part will have like a glowing element which reacts to the voice … when
/// switching between voices, the top element can show different types of glows").
///
/// Two things change with the voice, not one. Colour alone would make the row of pills and the
/// bloom say the same thing twice; a *form* as well means each voice has a light of its own shape
/// — an orb, a low band, two lobes, a ring, a core under a broad halo — so switching reads as a
/// different instrument rather than a hue rotation. The form is taken from the voice's place in
/// the row, so a voice added to the manifest gets one for nothing.
///
/// The level comes from `VoiceEnvelope`, which reads the clip's word timings rather than the
/// player's meters: `T2S_SILENT=1` pins the player's output at zero, and a glow driven by metering
/// would be dead in every frame the simulator recipe photographs.
///
/// Drawn behind the pills and bleeding up through the status area, with no edge of its own — it is
/// light, so what it meets it meets by fading out.
struct VoiceGlow: View {
    var voice: String
    var voices: [String]
    /// `VoiceEnvelope.floor`…1, once a frame.
    var level: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far down the screen the bloom reaches. Tall enough that the pills sit inside it rather
    /// than under its edge.
    static let height: CGFloat = 300

    /// The shapes a voice's light can take. Cycled by the voice's place in the row.
    enum Form: CaseIterable {
        /// One soft ball of light, centred, high.
        case orb
        /// A wide shallow wash across the whole crown, like a sky.
        case band
        /// Two overlapping blooms, offset either side — a light with two sources.
        case lobes
        /// A bright rim with a darker middle: the light of a mouth rather than of a lamp.
        case ring
        /// A tight hot core standing inside a much broader halo.
        case core

        static func of(_ voice: String, in voices: [String]) -> Form {
            let index = voices.firstIndex(of: voice) ?? 0
            return allCases[index % allCases.count]
        }
    }

    var body: some View {
        let colour = VoicePalette.glow(for: voice, in: voices)
        let form = Form.of(voice, in: voices)
        // The level read as *presence*, not as opacity outright. `VoiceEnvelope` sits at its floor
        // between words, which is most of any given frame — mapped straight through, the glow was
        // a fifth of its strength almost all the time and barely registered in the photograph. A
        // lamp that is lit is lit: the floor buys most of the brightness and the words buy the
        // rest, so the light is always present and still visibly breathes.
        //
        // Reduce Motion takes the middle of that range and stays there: the glow still says which
        // voice is chosen, it just no longer moves while it says it.
        let breath = reduceMotion ? 0.8 : 0.62 + 0.38 * level
        GeometryReader { geo in
            ZStack {
                ForEach(Array(lamps(for: form).enumerated()), id: \.offset) { _, lamp in
                    RadialGradient(stops: lamp.stops(colour, breath: breath),
                                   center: .center,
                                   startRadius: 0,
                                   endRadius: max(geo.size.width * lamp.radius * (0.86 + 0.14 * breath), 1))
                        .frame(width: geo.size.width * lamp.radius * 2.4,
                               height: geo.size.width * lamp.radius * 2.4 * lamp.squash)
                        .offset(x: geo.size.width * lamp.x, y: geo.size.height * lamp.y)
                        // Light adds to light: where two lamps of a `.lobes` voice cross they
                        // should brighten, not sit one over the other. Inside the compositing
                        // group below, so they sum with each other and the sum is then laid over
                        // the ground normally — `plusLighter` against the page itself would blow
                        // out the near-white ground of the light theme.
                        .blendMode(.plusLighter)
                }
            }
            .compositingGroup()
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .blur(radius: 26)
        }
        .frame(height: Self.height)
        // Held to the crown. The glow is drawn *over* the passage — it has to be, because the
        // crown's solid ground is what hides the text and the light has to be seen on top of that
        // — so without this its bloom spills down across the first readable lines and tints them.
        // Michael's blue was washing the top third of the passage. Light comes from above and
        // falls off; this is that, and it fades rather than clips, because a hard cut on a
        // 26 pt blur is a line across the screen.
        .mask(
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: 0.42),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // No animation on `level`. The scene is already inside a `TimelineView(.animation)`, so
        // this redraws every frame anyway, and hanging an implicit animation off a value that
        // changes every frame is what made the Reader's scrubber stutter — each frame starts a
        // new interpolation the next frame interrupts. The swell is in `VoiceEnvelope`'s own
        // attack and decay, where it can be tested. Only the change of voice animates, because
        // that is a step between two forms rather than a value in motion.
        .animation(.smooth(duration: 0.45), value: voice)
    }

    /// One lamp in the bloom: where it sits as a fraction of the width and of the glow's height,
    /// how wide it is, how much it is squashed, how strong it is at full level, and — for a rim
    /// rather than a ball — how far out its light starts.
    private struct Lamp {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var radius: CGFloat
        var squash: CGFloat = 1
        var opacity: Double
        /// Where the light begins, as a fraction of the radius. 0 is a ball, bright in the middle;
        /// anything above it is an annulus, dark in the middle and brightest at `inner` and the rim
        /// half way between. A stroked circle blurred this far would read as a smudge, and a
        /// radial gradient cannot be given a dark middle any other way.
        var inner: Double = 0

        /// The lamp's light as gradient stops, at `breath` of its full strength.
        func stops(_ colour: Color, breath: Double) -> [Gradient.Stop] {
            let lit = colour.opacity(opacity * breath)
            guard inner > 0 else {
                return [.init(color: lit, location: 0), .init(color: .clear, location: 1)]
            }
            return [.init(color: .clear, location: 0),
                    .init(color: .clear, location: inner),
                    .init(color: lit, location: (inner + 1) / 2),
                    .init(color: .clear, location: 1)]
        }
    }

    private func lamps(for form: Form) -> [Lamp] {
        switch form {
        case .orb:
            return [Lamp(y: -0.12, radius: 0.46, opacity: 0.64)]
        case .band:
            return [Lamp(y: -0.24, radius: 0.92, squash: 0.36, opacity: 0.50)]
        case .lobes:
            return [Lamp(x: -0.22, y: -0.06, radius: 0.38, opacity: 0.48),
                    Lamp(x: 0.22, y: -0.14, radius: 0.34, opacity: 0.48)]
        case .ring:
            return [Lamp(y: -0.10, radius: 0.52, opacity: 0.68, inner: 0.46)]
        case .core:
            return [Lamp(y: -0.10, radius: 0.72, opacity: 0.32),
                    Lamp(y: -0.10, radius: 0.18, opacity: 0.72)]
        }
    }
}

/// One colour per voice, shared by the row of pills and the glow above it so the two never
/// disagree — they are the same statement made twice, and a pill in one hue over a bloom in
/// another reads as a bug.
///
/// Spaced around the wheel by the voice's place in the row so neighbours never look alike, which
/// scales to any number of voices: a book added to the manifest adds a voice to this row too.
enum VoicePalette {
    /// One hue per voice, spaced around the wheel by its place in the row so neighbours never look
    /// alike. This scales to any number of voices: a book added to the manifest adds a voice to
    /// this row too.
    static func hue(for voice: String, in voices: [String]) -> Double {
        let index = voices.firstIndex(of: voice) ?? 0
        return (Double(index) / Double(max(voices.count, 1)) + 0.02).truncatingRemainder(dividingBy: 1)
    }

    /// The pill's fill: deep enough to carry `onAccent` white across it.
    static func colour(for voice: String, in voices: [String]) -> Color {
        Color(hue: hue(for: voice, in: voices), saturation: 0.66, brightness: 0.64)
    }

    /// The glow's, which is the same hue and nothing else the same. The pill's brightness is
    /// pitched for white text standing on it — laid over the near-white ground as a wash it came
    /// out as a brown stain rather than as light, which is what the first photograph showed. Light
    /// is bright and clean: high brightness, and saturation enough to still read as a colour after
    /// the ground has diluted it.
    static func glow(for voice: String, in voices: [String]) -> Color {
        Color(hue: hue(for: voice, in: voices), saturation: 0.78, brightness: 0.96)
    }

    /// `af_heart` → `Heart`.
    static func displayName(_ voice: String) -> String {
        let stem = voice.split(separator: "_").last.map(String.init) ?? voice
        return stem.prefix(1).uppercased() + stem.dropFirst()
    }
}
