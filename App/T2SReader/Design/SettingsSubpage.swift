// App/T2SReader/Design/SettingsSubpage.swift
import SwiftUI
import UIKit

/// A page pushed from Settings (owner, 2026-09-10): it has the whole screen — the root's bar goes
/// and the pager locks while it is up (`Chrome`) — and it draws its own way back, a circle at the top-left, with the page title at exactly the height every root
/// page's title sits (`Spacing.titleTop` below the safe area, not that plus a navigation bar). The
/// system bar is hidden for that; the swipe from the left edge still pops, see below.
///
/// Its ground is plain and opaque — a pushed page has to be, or the root shows through the push —
/// and the app's status band is laid over the whole thing, as on the root pager. It used to
/// paint the ramp into both the page ground and the bar, because a plain ground here hid the glow
/// and left only the bar's slice of it, cut off at the bar's foot (owner, 2026-09-10). Two copies
/// of the ramp meant two things to keep lined up, and both of them slipped at least once. One copy,
/// on top, has nothing to line up with.
struct SettingsSubpage: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(Chrome.self) private var chrome
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content
            .background {
                // Anchored to the window's top by measurement, not by `ignoresSafeArea`: with that
                // alone a pushed page's background sat one status-bar height low, so its copy of
                // the ramp disagreed with the root bar's and a seam showed under the status bar.
                GeometryReader { geo in
                    let top = geo.frame(in: .global).minY
                    Tokens.ground
                        .frame(width: geo.size.width, height: geo.size.height + top + 120)   // past the foot too
                        .offset(y: -top)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { chrome.subpageDepth += 1 }
            .onDisappear { chrome.subpageDepth -= 1 }
            // The bar plain, and measured. An overlay's reader sits inside the safe area and
            // reports its inset as zero, so `TopFade(inset:)` from it was a 30 pt bar at the status
            // bar's foot rather than one that holds through it; the content's top in the window is
            // the inset the bar must cover, and the offset takes it there.
            //
            // The light over it is the status band's, drawn in a window above this page
            // (`StatusBandHost`) and not installed here at all. This page painted its own rims
            // until 2026-09-15, and the measured shift above was deliberately *not* applied to
            // them: a rim takes itself to the window's edge, so the offset carried its lit edge
            // another status bar past it, off the screen, leaving the sides lit and the top gone
            // (owner, 2026-09-12, twice on the Voice page — cut at the content's top without it,
            // hoisted off the top with both). From its own window there is no content's-top left
            // to correct for.
            .overlay {
                GeometryReader { geo in
                    let top = geo.frame(in: .global).minY
                    // The band's ramp, exactly as the root pages grow it. A pushed page used to
                    // draw the plain 30 pt edge whatever was happening, so while a warm-up was up
                    // its title stood crisp and hard-edged under the rows while every root page's
                    // was veiled and read through — one element, two looks, decided by which screen
                    // you happened to be on (owner, 2026-09-15: "the other pages don't have the
                    // veil effect").
                    let warming = env.appStatus.isShowing
                    TopFade(inset: top,
                            extra: warming ? TopFade.warmSolid : 0,
                            fade: warming ? TopFade.warmFade : TopFade.fadeHeight)
                        .offset(y: -top)
                        .animation(.easeInOut(duration: StatusGlow.leave), value: warming)
                }
            }
            // **After the ground, not before it.** This was applied first, so the fade above drew
            // over it — harmless at 30 pt, where the circle sat in the ramp and stayed legible, and
            // not harmless at all once the band grew that fade to its full 36 pt of solid: the
            // circle went under it and a pushed page had no visible way back for as long as a
            // warm-up lasted. A page's own control belongs above the page's own ground.
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: { CircleGlyph(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    .padding(.leading, Spacing.margin)
                    .padding(.top, 12)
            }
    }
}

extension View {
    func settingsSubpage() -> some View { modifier(SettingsSubpage()) }
}

/// UIKit turns the edge-swipe pop off when the navigation bar is hidden; a Settings subpage hides
/// it (above) and still wants the swipe. Taking the recognizer's delegate keeps the gesture alive,
/// and allowing it only past the root keeps the pager from being dragged.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
