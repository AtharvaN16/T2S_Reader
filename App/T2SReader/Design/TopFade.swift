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
/// up the root pager passes `warmSolid` and `warmFade`, so the ground carries the rows and then
/// thins out across the title, which stays readable through it. Every other host passes nothing:
/// the line is only ever drawn over the root pages, so a sheet or a Settings subpage has nothing
/// to hold clear.
struct TopFade: View {
    /// The safe-area top inset of the screen this covers; the caller reads it from a `GeometryReader`.
    var inset: CGFloat
    /// Solid ground below the inset, before the fade. Zero everywhere but the root pager mid-warm-up.
    var extra: CGFloat = 0
    /// How far the ramp runs below the solid band. Longer while the warm-up is up, so the page
    /// title dissolves under it rather than meeting an edge; see `warmFade`.
    var fade: CGFloat = fadeHeight
    static let fadeHeight: CGFloat = 30

    /// The warm-up's ground, as a solid band and a fade over it, both passed by the root pager.
    ///
    /// The two numbers are the whole design, and both cuts before this one got them wrong in
    /// opposite directions. Solid to 54 — the reach of the line's three rows — put the band's hard
    /// edge through the middle of the 34 pt title that starts at `Spacing.titleTop`, and a page
    /// title sliced across the glyphs reads as a rendering bug. Solid to 84 fixed the slice by
    /// covering the title outright, which is not what a fade is for (owner, 2026-09-12: "the title
    /// should be visible, the reason we are going with the faded look is so that some of the title
    /// can be seen through").
    ///
    /// So the solid stops short of the title's top at 40, so no hard edge ever lands on a letter,
    /// and a long ramp runs from there: still most of the way opaque behind the bar at 44…49, and
    /// thinning across the title so "Home" comes through veiled at the crown and clearer at the
    /// foot. It is the ramp that crosses the title, never an edge.
    ///
    /// 36 and 116 since the owner asked for it lower and smoother (2026-09-12: "move the indicator
    /// fade slightly lower so more of the screen is covered and it is a smoother fade"), up from 28
    /// and 76. The extra 8 of solid buys the bar a little more ground to sit on without reaching
    /// the title, and the ramp being half again as long is what makes it read as smooth: the same
    /// eased curve spread over more points has a shallower slope everywhere, so there is less of a
    /// gradient across any one row of the page. It now clears at 152 rather than 104, which puts
    /// the foot of it below the section header instead of on top of it.
    static let warmSolid: CGFloat = 36
    static let warmFade: CGFloat = 116

    var body: some View {
        let solid = inset + extra
        let height = solid + fade
        // Ground, never the warm-up glow: a `warm` flag here used to make the bar paint the ramp
        // so bar and page were one surface, and that only held while every layer under the bar was
        // transparent. The glow is a `WarmRim` over this now (`RootPager`), which needs nothing of
        // the bar.
        Tokens.ground
            .mask(Self.shape(solidThrough: solid, fade: fade))
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

/// A soft edge on a scrolling area that is not the screen's own top — the bookmarks list under its
/// header, a bookmark's words under theirs (owner, 2026-09-12: "use bottom and top fade"). The same
/// eased ramp `TopFade` lays over the status bar, with no solid part: ground at the edge easing to
/// clear a few points in, so a row slides out of the page rather than stopping at a cut.
///
/// Ground, so it only works over the page's own ground — which is every page that uses it.
struct EdgeFade: View {
    var edge: VerticalEdge
    /// Shorter at the top, where the content passes under a header that is already there, and
    /// taller at the foot, where there is nothing below it to stop the eye.
    var height: CGFloat = 28

    var body: some View {
        Tokens.ground
            .mask(TopFade.shape(solidThrough: 0, fade: height).scaleEffect(y: edge == .bottom ? -1 : 1))
            .frame(height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .bottom ? .bottom : .top)
            // Through the home-indicator inset when it backs the screen's own foot (`BottomFade`'s
            // reasoning): the bookmarks list stops at the inset's top edge, but its ground does not,
            // so without this a row showed in the strip under the indicator (owner, 2026-09-13).
            .ignoresSafeArea(edges: edge == .bottom ? .bottom : [])
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
