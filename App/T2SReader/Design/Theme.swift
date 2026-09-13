import SwiftUI
import UIKit
import T2SApp

/// The theme choice applies to the whole app (spec 2026-09-07 §6). `system` means no preference.
extension ReaderTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The same choice as UIKit states it. `system` is `.unspecified` — the absence of an override,
    /// not a third colour — so dropping it hands the screen back to the device's own setting.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Applied once, at the root of the window (`RootPager`), and that is the whole of it: every page,
/// pushed page, sheet, cover and UIKit text view in the app follows from here.
///
/// `preferredColorScheme` alone cannot do that job, which is what the theme was built on until
/// 2026-09-12 and why the Voice and Cloud pages kept their old colours after a change (owner; and
/// the two goes at it before this one). It is a *preference*: it travels up to the presentation it
/// was declared in and colours that presentation's own SwiftUI tree. A page pushed by
/// `NavigationStack` is not in that tree. SwiftUI hosts the stack in a `UINavigationController` of
/// its own and — measured, on the phone's iOS — pins that controller's traits with
/// `setOverrideTraitCollection(_:forChild:)` at the moment the stack is *built*, then never touches
/// them again. So the pushed page wears the scheme the app happened to be in when Settings was
/// first drawn: the change does not reach it, and neither does the next push, because the pin is on
/// the stack, not on the page. Declaring `preferredColorScheme` on the pushed page does not help
/// either — it too travels up, past the pin, to the same root.
///
/// The pin is on the *controller*, so we beat it below the controller: a `traitOverrides` on each
/// view controller's own view, which UIKit applies after everything it inherits and passes down to
/// every subview — the pushed pages among them. The window carries the override too, for the
/// screen's own furniture and for anything presented later, which then starts out right and needs
/// nothing from us.
private struct AppTheme: ViewModifier {
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        let theme = env.preferences.theme
        content
            // Still declared: it is the documented way, it settles SwiftUI's own `\.colorScheme`
            // for the root tree on the first frame — before `WindowTheme` has a window to write on
            // — and so the app never opens on a flash of the device's scheme.
            .preferredColorScheme(theme.colorScheme)
            .background(WindowTheme(style: theme.interfaceStyle).frame(width: 0, height: 0))
    }
}

/// Writes the theme onto the window and onto every view controller standing in it. Zero-sized and
/// invisible: it is here to reach `window`, nothing else.
private struct WindowTheme: UIViewRepresentable {
    var style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> StyleView { StyleView() }

    func updateUIView(_ view: StyleView, context: Context) { view.style = style }

    final class StyleView: UIView {
        /// Only a real change walks the tree: `updateUIView` runs on every redraw of the root, and
        /// the walk is for the theme moving, not for the app moving.
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { if style != oldValue { apply() } }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()                                     // the first application: `style` is set before there is a window
        }

        private func apply() {
            guard let window else { return }
            window.overrideUserInterfaceStyle = style
            if let root = window.rootViewController { apply(to: root) }
        }

        private func apply(to controller: UIViewController) {
            // A controller whose view has not loaded is left alone rather than forced to load: when
            // it does load it is already inside a view we have written on, and inherits.
            if controller.isViewLoaded {
                if style == .unspecified {
                    controller.view.traitOverrides.remove(UITraitUserInterfaceStyle.self)
                } else {
                    controller.view.traitOverrides.userInterfaceStyle = style
                }
            }
            controller.children.forEach(apply(to:))
            if let presented = controller.presentedViewController { apply(to: presented) }
        }
    }
}

extension View {
    func appTheme() -> some View { modifier(AppTheme()) }
}
