import SwiftUI
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
}

/// Applied to the root pager and to the Reader page (a full-screen cover is its own presentation),
/// so every screen, sheet and the Reader's UIKit text view follow one choice.
private struct AppTheme: ViewModifier {
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.preferredColorScheme(env.preferences.theme.colorScheme)
    }
}

extension View {
    func appTheme() -> some View { modifier(AppTheme()) }
}
