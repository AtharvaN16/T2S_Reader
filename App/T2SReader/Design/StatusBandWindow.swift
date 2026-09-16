// App/T2SReader/Design/StatusBandWindow.swift
import SwiftUI
import T2SApp
import UIKit

/// A window that can be seen through and never touched: `hitTest` answers nil for every point, so
/// every tap, drag and edge-swipe lands on the app underneath as though this window were not there.
///
/// It has to be a window-level refusal rather than `allowsHitTesting(false)` inside SwiftUI. A
/// `UIWindow` is a responder in its own right: the hosting controller's view can decline a touch
/// and the window will still claim it, because `UIWindow.hitTest` falls back to itself when no
/// subview answers. A full-screen window over the app that does that is an app that has stopped
/// responding — the band would eat the Reader's tap-to-hide-chrome, the pager's page swipe and the
/// back-swipe of every pushed Settings page at once.
final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// The status band's own window, and the reason the band has one.
///
/// **The band is the app's, and a SwiftUI overlay can only ever belong to a page.** Until
/// 2026-09-15 each surface applied `.appStatusBand()` inside its own body. That works for surfaces
/// that share one presentation, but the Reader is a `fullScreenCover` — a separate presentation the
/// root pager's band cannot reach into — so the Reader had to carry a second copy applied inside
/// `ReaderPage`'s body. Which made the band part of the presented content: opening a book slid the
/// cover up from the bottom of the screen and the glow and the rows rode up with it (owner,
/// 2026-09-15, watching the light travel with the page). Nothing about a voice download moves when
/// a book opens, and a status that appears to be attached to the book is saying it does.
///
/// A second `UIWindow` one level above `.normal` is the only place in UIKit that is genuinely above
/// every presentation: sheets, `fullScreenCover`s and pushed navigation controllers all present
/// *within* the app's window, so a window over it is over all of them, with no page's transform,
/// transition or clip applied to it. One band exists, for the life of the app, wherever the reader
/// is.
///
/// **What a window costs.** Two things, and both are paid for here. It would swallow every touch —
/// answered by `PassthroughWindow` above and by a hosting view that is not interactive. And it is
/// outside the SwiftUI environment, so the band cannot read `\.readerPalette` and learn the book's
/// paper; `StatusAppearance` is the object that carries it across instead (see `StatusBand.swift`).
/// `AppEnvironment` *is* injected here, because it is one object we can hand across by hand.
@MainActor
final class StatusBandHost {
    /// The live host, which is also the strong reference the window needs. A `UIWindow` is not
    /// retained by its scene: drop this and the window is deallocated on the next turn of the run
    /// loop and the band simply never appears, with nothing on screen to say why.
    private static var shared: StatusBandHost?
    /// How many turns the attach has left to find a scene. See `attach`.
    private static var attemptsLeft = 20

    private let window: PassthroughWindow

    private init(scene: UIWindowScene, environment: AppEnvironment) {
        let controller = UIHostingController(rootView: StatusBandOverlay().environment(environment))
        // Both, and neither is redundant: clear so the band is the only thing this window paints,
        // and non-interactive so the hosting view declines touches before the window is asked.
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        window = PassthroughWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        window.rootViewController = controller
        // Visible, but never `makeKeyAndVisible`: key status belongs to the app's own window, and
        // taking it from a window that refuses every touch would leave the keyboard and the
        // first responder chain hanging off a window that can never own them.
        window.isHidden = false
    }

    /// Puts the band on screen, once. Safe to call from any `onAppear` that may run more than
    /// once — a second call with a host already standing is a no-op, and two hosts would be two
    /// windows drawing two rim pairs, which *add*: the same doubled light the root pager and a
    /// pushed Settings page cost us on 2026-09-12.
    ///
    /// Called from `T2SReaderApp`'s existing `.onAppear`, which is the least invasive hook the app
    /// has: the alternative is a `UIApplicationDelegateAdaptor` and a scene delegate, which this
    /// app does not otherwise need and which would exist solely to hold this one line. By the time
    /// a `WindowGroup`'s root view appears its scene is connected, so the lookup below normally
    /// succeeds first time; the retry is for the case where it does not, because a band that
    /// silently never attached is a defect with no symptom but an absence.
    static func attach(to environment: AppEnvironment) {
        guard shared == nil else { return }
        guard let scene = foremostScene else {
            guard attemptsLeft > 0 else { return }
            attemptsLeft -= 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                attach(to: environment)
            }
            return
        }
        shared = StatusBandHost(scene: scene, environment: environment)
    }

    /// The scene the reader is looking at. This app has exactly one, but `connectedScenes` can
    /// briefly hold an unattached or background one either side of a launch, and a window built on
    /// that one would be sized by a screen nobody is looking at.
    private static var foremostScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first { $0.activationState != .unattached }
    }
}
