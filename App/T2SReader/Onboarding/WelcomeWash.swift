// App/T2SReader/Onboarding/WelcomeWash.swift
import SwiftUI
import T2SApp

/// The light behind the welcome's name (the owner, 2026-09-18: "add slight glow in the welcome
/// screen", with Queue's own welcome as the reference — a pale drift of colour across an otherwise
/// plain ground).
///
/// **Slight is the specification.** Two very soft blooms, well under a sixth opacity, in the app's
/// own two lights: the blue it glows with while it works (`Tokens.glow`) high and left, the accent
/// orange low and right. Enough that the ground is not flat white behind three words, not enough to
/// read as a gradient someone chose.
///
/// It is still, not breathing. The rim on the voice page moves because it is saying something —
/// this voice, these words — where this is saying nothing but "the screen is not empty", and a
/// pulse under a name reads as a notification. The scene it sits in lasts about three seconds.
///
/// **No blur, and the radii are large on purpose.** A blurred bloom inside a bounded frame lights
/// its own frame edges, which is how the crown's first cut ended up with a visible rectangle in
/// it. These are radial gradients that reach past the screen on every side and are drawn straight,
/// so there is no edge anywhere for one to find.
struct WelcomeWash: View {
    var body: some View {
        GeometryReader { geo in
            let reach = max(geo.size.width, geo.size.height)
            ZStack {
                bloom(Tokens.glow, opacity: 0.13, reach: reach)
                    .offset(x: -geo.size.width * 0.28, y: -geo.size.height * 0.22)
                bloom(Tokens.accent, opacity: 0.10, reach: reach)
                    .offset(x: geo.size.width * 0.30, y: geo.size.height * 0.24)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bloom(_ colour: Color, opacity: Double, reach: CGFloat) -> some View {
        RadialGradient(stops: [.init(color: colour.opacity(opacity), location: 0),
                               .init(color: colour.opacity(opacity * 0.45), location: 0.45),
                               .init(color: .clear, location: 1)],
                       center: .center,
                       startRadius: 0,
                       endRadius: reach * 0.75)
            .frame(width: reach * 1.5, height: reach * 1.5)
    }
}
