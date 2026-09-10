// App/T2SReader/Design/SettingsSubpage.swift
import SwiftUI
import UIKit

/// A page pushed from Settings (owner, 2026-09-10): it has the whole screen — the root's bar goes
/// and the pager locks while it is up (`Chrome`) — and it draws its own way back, a circle at the top-left, with the page title at exactly the height every root
/// page's title sits (`Spacing.titleTop` below the safe area, not that plus a navigation bar). The
/// system bar is hidden for that; the swipe from the left edge still pops, see below.
///
/// Its ground is `WarmGround`, not `ground`: a pushed page is opaque (the root would show through
/// the push otherwise), and a plain ground here hid the warm-up glow behind it, so on the Voice
/// page only the root bar's slice of the glow showed, cut off at the bar's foot (owner,
/// 2026-09-10). Painting the same ramp the bars and the veil paint makes it one surface again.
struct SettingsSubpage: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(Chrome.self) private var chrome

    func body(content: Content) -> some View {
        content
            .background {
                // Anchored to the window's top by measurement, not by `ignoresSafeArea`: with that
                // alone a pushed page's background sat one status-bar height low, so its copy of
                // the ramp disagreed with the root bar's and a seam showed under the status bar.
                GeometryReader { geo in
                    let top = geo.frame(in: .global).minY
                    WarmGround()
                        .frame(width: geo.size.width, height: geo.size.height + top + 120)   // past the foot too
                        .offset(y: -top)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { chrome.subpageDepth += 1 }
            .onDisappear { chrome.subpageDepth -= 1 }
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: { CircleGlyph(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    .padding(.leading, Spacing.margin)
                    .padding(.top, 12)
            }
            // Warm like the root's bar: the page under it is the warm ground now, so a plain bar
            // fading over it would lighten the fade zone a shade (measured, 2026-09-10). Anchored
            // like the background, by measurement: an overlay's reader sits inside the safe area
            // and reports its inset as zero, so `TopFade(inset:)` from it was a 30 pt bar at the
            // status bar's foot — a copy of the ramp one inset low, fading over the right one —
            // and the band it left there was the seam on the Voice page (measured, 2026-09-10).
            // The content's top in the window is the inset the bar must hold through.
            .overlay {
                GeometryReader { geo in
                    let top = geo.frame(in: .global).minY
                    TopFade(inset: top, warm: true).offset(y: -top)
                }
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
