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
final class IslandWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        // The hosting controller's own root view covers the screen and is not a control. Anything
        // deeper is the capsule or something on it.
        return hit === rootViewController?.view ? nil : hit
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
        let host = UIHostingController(rootView: MockIslandRoot().environment(environment))
        host.view.backgroundColor = .clear
        let created = IslandWindow(windowScene: scene)
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

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if let message = env.island.message {
                MockIsland(message: message, cover: env.island.cover, action: env.island.action,
                           onDismiss: { env.island.dismiss() })
            }
        }
        .ignoresSafeArea()
    }
}
