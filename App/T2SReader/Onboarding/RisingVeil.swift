// App/T2SReader/Onboarding/RisingVeil.swift
import SwiftUI

/// The welcome's wipe: a sheet that rises from the foot of the screen to the crown, uncovering
/// whatever stands on it as its edge passes (design:
/// `docs/superpowers/specs/2026-09-16-onboarding-reel-welcome-page-design.md`; the owner,
/// 2026-09-16: "a fade overlay move from bottom to the top revealing welcome to T2S … after that
/// the overlay will again shift to show a page with an excerpt").
///
/// Used twice on the same scene, for the two rises: the first carries the app's name up over the
/// reel, the second carries the page up over the name. Each is the same sheet travelling, which is
/// why this is a mask rather than a transition — the content is laid out in its final place from
/// the first frame and simply becomes visible from the bottom up, so nothing slides, reflows or
/// arrives late. A `.move(edge: .bottom)` transition would have dragged the text up the screen
/// with it, and the passage has to be where it will stay before its first word is spoken.
///
/// The edge is not a line. It is the app's own fade curve (`BottomFade.stops`, smoothstep
/// squared), so the sheet meets what it is covering the way every other fade in the app does — a
/// straight ramp leaves a Mach band, and a hard edge would read as a shutter.
struct RisingVeil<Content: View>: View {
    /// 0 with the sheet below the screen and nothing showing, 1 with it home and all of it showing.
    var progress: Double
    /// How tall the soft edge is. Generous: this is a whole screen being uncovered, not a bar's
    /// foot, and a short ramp travelling fast reads as a line crossing the glass.
    var edge: CGFloat = 160
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            content()
                .frame(width: geo.size.width, height: geo.size.height)
                .mask { sheet(in: geo.size) }
        }
    }

    /// The sheet, as one gradient down the screen.
    ///
    /// The travel is expressed in the gradient's *unit points* rather than as a masking rectangle
    /// of a measured height, because the ramp has to leave the screen at both ends of the journey:
    /// clear of the foot at rest, and clear off the crown when home. A `LinearGradient` holds its
    /// first colour above `startPoint` and its last below `endPoint` however far outside `0...1`
    /// those sit, so putting the ramp below the foot gives a screen that is wholly uncovered, and
    /// putting it above the crown gives one that is wholly covered — with no extra frame, offset
    /// or clip to keep in step.
    private func sheet(in size: CGSize) -> some View {
        // The ramp's height as a share of the screen's, and where its foot has reached.
        //
        // The travel is the screen *plus a ramp at each end*: the ramp starts wholly below the
        // foot, so nothing is covered at rest, and finishes wholly above the crown, so everything
        // is. Ending the journey with the ramp's foot on the crown — which is what `(1 + ramp) *
        // (1 - progress)` did — left the last few points of the screen under the clear end of the
        // ramp, and a sliver of the beat underneath showed along the top edge. Caught in the
        // photograph of the name, where a cover was still visible above it.
        let ramp = edge / max(size.height, 1)
        let bottom = (1 + ramp) - progress * (1 + 2 * ramp)
        return LinearGradient(stops: BottomFade.stops(color: .black),
                              startPoint: UnitPoint(x: 0.5, y: bottom - ramp),
                              endPoint: UnitPoint(x: 0.5, y: bottom))
    }
}
