// App/T2SReader/Design/Tokens.swift
import SwiftUI
import UIKit

/// Spec §2.4.2: semantic tokens only; views never name a literal color. Light / dark resolve
/// through a dynamic UIColor so the whole app follows the system or the user's theme.
enum Tokens {
    static let ground = dynamic(light: 0xF8F8F7, dark: 0x101010)
    static let surface = dynamic(light: 0xEEEEEC, dark: 0x1E1E1E)
    static let raised = dynamic(light: 0xFFFFFF, dark: 0x1A1A1A)
    static let ink = dynamic(light: 0x111111, dark: 0xF2F2F2)
    static let ink2 = dynamic(light: 0x8A8A8A, dark: 0x8E8E8E)
    static let ink3 = dynamic(light: 0xC9C9C7, dark: 0x3A3A3A)
    static let accent = dynamic(light: 0xFF7A1A, dark: 0xFF8C3A)
    static let accentSoft = dynamic(light: 0xFF7A1A, dark: 0xFF8C3A, lightAlpha: 0.18, darkAlpha: 0.22)
    /// text on `accent`
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let positive = dynamic(light: 0x22A559, dark: 0x34C070)
    static let destructive = dynamic(light: 0xE5453B, dark: 0xFF5A50)

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return UIColor(rgb: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
