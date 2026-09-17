// App/T2SReader/Design/MockIslandWindow.swift
import SwiftUI
import UIKit

/// A window that is touchable *only* where the capsule is.
///
/// `PassthroughWindow` (the status band's, `StatusBandWindow.swift:15`) refuses every touch,
/// which is right for a band that is only ever read. This capsule has a Play button, so it must
/// claim touches inside itself and refuse them everywhere else: a window that claimed the whole
/// screen would eat the Reader's tap-to-hide-chrome, the pager's page swipe and every pushed
/// Settings page's back-swipe, exactly as the band's doc comment warns.
///
/// **Do not try to tell the capsule apart by view identity.** That is what this window did until
/// 2026-09-16, and it refused *every* touch including the Play button's: `_UIHostingView`
/// overrides `hitTest` and answers **itself** at every point inside its bounds, so
/// `hit === rootViewController?.view` was true everywhere and the method returned nil everywhere
/// (measured on the simulator; review C1). The `_UIShapeHitTestingView`s SwiftUI builds under the
/// host are never returned to a caller — SwiftUI dispatches to them internally, which is also why
/// handing the host view back is enough for the Button to work.
///
/// So the window is told where the capsule is instead. `MockIsland` publishes its own frame as it
/// lays out and clears it on the way out, and this tests the point against that rect: one
/// rectangle, in this window's coordinates, that is the whole of what the app may not have.
final class IslandWindow: UIWindow {
    /// The capsule's frame in this window's coordinates. `.zero` whenever nothing is showing,
    /// which is most of the time — and a `.zero` rect contains no point, so a hidden capsule
    /// claims nothing.
    var touchable: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard touchable.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// The capsule's window, one level above the status band's, for the life of the app.
@MainActor
enum MockIslandHost {
    private static var window: IslandWindow?

    /// Idempotent — safe to call from `onAppear`, which can run again.
    static func attach(to environment: AppEnvironment) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState != .unattached })
        else { return }
        let created = IslandWindow(windowScene: scene)
        // Set explicitly, as `StatusBandHost` does: the capsule now reports a rect in this
        // window's coordinates and `hitTest` compares points against it, so the window's own
        // frame has to be the screen's and not whatever a default leaves it at.
        created.frame = scene.coordinateSpace.bounds
        let root = MockIslandRoot(onCapsuleFrame: { [weak created] rect in created?.touchable = rect })
        let host = UIHostingController(rootView: root.environment(environment))
        host.view.backgroundColor = .clear
        created.rootViewController = host
        created.windowLevel = .normal + 2
        created.backgroundColor = .clear
        created.isHidden = false
        window = created
    }
}

/// What the window draws: whatever the centre is holding, and nothing when it holds nothing.
private struct MockIslandRoot: View {
    @Environment(AppEnvironment.self) private var env
    /// Where the capsule is, in window coordinates, for `IslandWindow.hitTest`.
    var onCapsuleFrame: (CGRect) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if let message = env.island.message {
                MockIsland(message: message, cover: env.island.cover, action: env.island.action,
                           onDismiss: { env.island.dismiss() },
                           onCapsuleFrame: onCapsuleFrame)
            }
        }
        .ignoresSafeArea()
    }
}
