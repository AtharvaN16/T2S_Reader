// App/T2SReader/Design/BottomFade.swift
import SwiftUI

/// The foot's ground, for a bar that sits over a scrolling page: solid behind the bar, thinning to
/// nothing above it, so a row slides out from under the bar instead of being sliced by it. The root
/// pages have had this since the bottom bar arrived (`RootPager.bottomFill`, 180 pt over the page
/// row); this is the same curve as a view, so a sheet's commit bar can have it too — the voice
/// sheet's bar painted a flat `ground` and cut the list off at a straight line (owner, 2026-09-12).
///
/// `TopFade`'s opposite number, and built the other way round for a reason: the top one masks a
/// solid `ground`, because it has a safe-area inset to cover and a height only a `GeometryReader`
/// knows. A bar's background is already exactly the size of the bar, so this one grows *out* of
/// whatever it backs — `padding(.top, -fade)` hands the child a taller proposal and lifts it — and
/// needs nothing measured.
struct BottomFade: View {
    /// How far the ramp runs above the solid ground.
    var fade: CGFloat = fadeHeight

    /// 72 pt: a little over a key's height, which is the shortest ramp that still reads as a fade
    /// rather than a soft edge. The root pager's own is 180 because it has a mini-player's band to
    /// clear as well; a sheet's bar has nothing above it but the list.
    static let fadeHeight: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(stops: Self.stops(), startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
            Tokens.ground
        }
        // Negative padding, so the ramp sits *above* the bar it backs: the child is proposed the
        // bar's height plus `fade` and placed `fade` higher, which puts `Tokens.ground` exactly
        // over the bar and the ramp over the page. A background never clips, so nothing is lost.
        .padding(.top, -fade)
        // Down through the home-indicator inset as well: a bar in a `safeAreaInset` stops at the
        // inset's top edge, but the scroll view behind it does not, so without this a row shows in
        // the strip under the key.
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The ramp, as gradient stops: clear at the top, `ground` by `fadeEnd`, solid from there down.
    ///
    /// Smoothstep squared, not a straight line. A linear fade that stops dead where the solid
    /// begins leaves a kink the eye reads as a line across the screen (a Mach band) — which is the
    /// one thing a fade is there to avoid. Squaring keeps the upper half of the ramp light, so the
    /// page shows through most of it and only the last stretch is ground.
    ///
    /// - Parameter fadeEnd: where the ramp finishes, as a fraction of the gradient's own height.
    ///   1 when the gradient is only the ramp (this view); less when the caller draws ramp and
    ///   solid ground as one gradient (`RootPager.bottomFill`).
    static func stops(fadeEnd: Double = 1, steps: Int = 12) -> [Gradient.Stop] {
        var stops = (0...steps).map { i -> Gradient.Stop in
            let t = Double(i) / Double(steps)
            let eased = pow(t * t * (3 - 2 * t), 2)
            return .init(color: Tokens.ground.opacity(eased), location: fadeEnd * t)
        }
        if fadeEnd < 1 { stops.append(.init(color: Tokens.ground, location: 1)) }
        return stops
    }
}
