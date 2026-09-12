// App/T2SReader/Design/TopFade.swift
import SwiftUI

/// The top edge's ground, for pages whose content scrolls up under the status bar: solid through
/// the safe-area inset — a clock over a row's title was the sharp cut the owner pointed at
/// (2026-09-09, ElevenReader's top edge as the reference) — then a short, light fade below it, so a
/// row slides out from under the bar instead of being sliced by it. Kept short and light on the
/// owner's word ("not very intense or tall"): `fadeHeight` is a sixth of the bottom bar's, and the
/// same eased ramp as `RootPager.bottomFill` so no line shows where the fade meets the page.
/// Anchored to the screen top the way the bottom fill is anchored to its foot — a fixed height
/// under `ignoresSafeArea` alone would float — and off for hit testing so the page keeps its taps.
///
/// **`extra` is the warm-up's room** (owner, 2026-09-12). The page title used to hold its own
/// clearance: `Spacing.titleTop` was 56 because the warm-up's three rows reach `inset + 54` and a
/// title any higher would have sat in them. The clearance lives here instead — while the glow is
/// up the root pager passes `warmBand` and the solid band grows to cover the rows and the title, so
/// the bar reads against ground rather than against whatever row happens to be scrolled under it,
/// and the fade below picks up where it always did. The title is 40 now and is simply covered for
/// the length of the wait. Every other host passes nothing: the line is only ever drawn over the
/// root pages, so a sheet or a Settings subpage has nothing to hold clear.
struct TopFade: View {
    /// The safe-area top inset of the screen this covers; the caller reads it from a `GeometryReader`.
    var inset: CGFloat
    /// Solid ground below the inset, before the fade. Zero everywhere but the root pager mid-warm-up.
    var extra: CGFloat = 0
    static let fadeHeight: CGFloat = 30

    /// What the root pages hold solid while the warm-up is up. It has to clear two things, and the
    /// first cut of this cleared only one: the line's own three rows reach `WarmUpLine.bandHeight`
    /// (54), but the 34 pt page title now starts at `Spacing.titleTop` (40) and runs to about 81,
    /// so a band that stopped at 54 cut "Home" in half and left its lower half ghosting through the
    /// fade (owner's screenshot, 2026-09-12). Covered or clear; half-covered reads as broken. 84
    /// puts the ground a few points past the title's descenders, and the fade below it falls on the
    /// section header, which is what a fade is for.
    static let warmBand: CGFloat = 84

    var body: some View {
        let solid = inset + extra
        let height = solid + Self.fadeHeight
        // Ground, never the warm-up glow: a `warm` flag here used to make the bar paint the ramp
        // so bar and page were one surface, and that only held while every layer under the bar was
        // transparent. The glow is a `WarmRim` over this now (`RootPager`), which needs nothing of
        // the bar.
        Tokens.ground
            .mask(Self.shape(solidThrough: solid, fade: Self.fadeHeight))
            .frame(height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The bar's shape, as a mask: solid through `solidThrough`, then an eased ramp to clear over
    /// `fade`. Smoothstep squared, mirrored — solid at the bar, zero slope into the page — so no
    /// line shows where the fade meets the page.
    static func shape(solidThrough: CGFloat, fade: CGFloat) -> some View {
        let height = solidThrough + fade
        let solidEnd = solidThrough / height
        let steps = 8
        var stops: [Gradient.Stop] = [.init(color: .black, location: 0), .init(color: .black, location: solidEnd)]
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let eased = pow((1 - t) * (1 - t) * (1 + 2 * t), 2)
            stops.append(.init(color: .black.opacity(eased), location: solidEnd + (1 - solidEnd) * t))
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom).frame(height: height)
    }
}
