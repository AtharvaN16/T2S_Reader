// App/T2SReader/Root/Chrome.swift
import SwiftUI
import UIKit

/// What the root shows around the pages. `isSubpageOpen` is true while a page pushed from Settings
/// is up (`SettingsSubpage` counts itself in and out): the bottom bar hides and the pager locks,
/// so the subpage has the screen and the only swipe left is the one back (owner, 2026-09-10).
@Observable
final class Chrome {
    var subpageDepth = 0
    var isSubpageOpen: Bool { subpageDepth > 0 }
}

/// Stops the page swipe while a subpage is up. SwiftUI's paged `TabView` is a
/// `UIPageViewController`, and its swipe is its queuing scroll view's; nothing in SwiftUI turns that
/// off, so this sits as a background of a page and reaches up to the nearest scroll view above it —
/// that queuing view, since a page's own `ScrollView` is a sibling, not an ancestor, of a
/// `.background`. Re-checked on every update, since the view hierarchy is built after the first.
struct PagerLock: UIViewRepresentable {
    @Environment(Chrome.self) private var chrome

    func makeUIView(context: Context) -> LockView { LockView() }

    func updateUIView(_ view: LockView, context: Context) {
        let locked = chrome.isSubpageOpen
        DispatchQueue.main.async { view.apply(locked: locked) }
    }

    final class LockView: UIView {
        func apply(locked: Bool) {
            var v: UIView? = superview
            while let view = v, !(view is UIScrollView) { v = view.superview }
            (v as? UIScrollView)?.isScrollEnabled = !locked
        }
    }
}
