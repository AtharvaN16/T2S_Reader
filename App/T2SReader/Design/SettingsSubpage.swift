// App/T2SReader/Design/SettingsSubpage.swift
import SwiftUI
import UIKit

/// A page pushed from Settings (owner, 2026-09-10): it has the whole screen — the root's bar goes
/// and the pager locks while it is up (`Chrome`) — and it draws its own way back, a circle at the top-left, with the page title at exactly the height every root
/// page's title sits (`Spacing.titleTop` below the safe area, not that plus a navigation bar). The
/// system bar is hidden for that; the swipe from the left edge still pops, see below.
///
/// Its ground is plain and opaque — a pushed page has to be, or the root shows through the push —
/// and the warm-up glow is a `WarmRim` laid over the whole thing, as on the root pager. It used to
/// paint the ramp into both the page ground and the bar, because a plain ground here hid the glow
/// and left only the bar's slice of it, cut off at the bar's foot (owner, 2026-09-10). Two copies
/// of the ramp meant two things to keep lined up, and both of them slipped at least once. One copy,
/// on top, has nothing to line up with.
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
                    Tokens.ground
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
            // The bar plain, the glow over it. Both are anchored by measurement: an overlay's
            // reader sits inside the safe area and reports its inset as zero, so `TopFade(inset:)`
            // from it was a 30 pt bar at the status bar's foot rather than one that holds through
            // it. The content's top in the window is the inset the bar must cover, and the same
            // shift puts the rim's lit edge on the window's top edge instead of the content's.
            .overlay {
                GeometryReader { geo in
                    let top = geo.frame(in: .global).minY
                    TopFade(inset: top).offset(y: -top)
                    WarmRim(edge: .top)
                        .frame(width: geo.size.width, alignment: .top)
                        .offset(y: -top)
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
