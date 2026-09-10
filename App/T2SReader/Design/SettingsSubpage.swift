// App/T2SReader/Design/SettingsSubpage.swift
import SwiftUI
import UIKit

/// A page pushed from Settings (owner, 2026-09-10): it has the whole screen — the root's bar goes
/// and the pager locks while it is up (`Chrome`) — and it draws its own way back, a circle at the top-left, with the page title at exactly the height every root
/// page's title sits (`Spacing.titleTop` below the safe area, not that plus a navigation bar). The
/// system bar is hidden for that; the swipe from the left edge still pops, see below.
struct SettingsSubpage: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(Chrome.self) private var chrome

    func body(content: Content) -> some View {
        content
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
            .overlay { GeometryReader { geo in TopFade(inset: geo.safeAreaInsets.top) } }
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
