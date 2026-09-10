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
struct TopFade: View {
    /// The safe-area top inset of the screen this covers; the caller reads it from a `GeometryReader`.
    var inset: CGFloat
    /// Paint the warm-up glow instead of ground while it shows (`WarmGround`). Only for a host
    /// whose page is transparent to the glow underneath — the root pager — so bar and page are one
    /// surface; a bar glowing over a plain page would be the seam this exists to remove.
    var warm = false
    static let fadeHeight: CGFloat = 30

    var body: some View {
        let height = inset + Self.fadeHeight
        Group {
            if warm { WarmGround() } else { Tokens.ground }
        }
        .mask(Self.shape(solidThrough: inset, fade: Self.fadeHeight))
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
