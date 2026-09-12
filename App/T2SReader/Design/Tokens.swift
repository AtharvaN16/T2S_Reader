// App/T2SReader/Design/Tokens.swift
import SwiftUI
import T2SApp
import UIKit

/// Spec §2.4.2: semantic tokens only; views never name a literal color. Light / dark resolve
/// through a dynamic UIColor so the whole app follows the system or the user's theme.
enum Tokens {
    static let ground = dynamic(light: 0xF8F8F7, dark: 0x101010)
    static let surface = dynamic(light: 0xEEEEEC, dark: 0x1E1E1E)
    static let raised = dynamic(light: 0xFFFFFF, dark: 0x1A1A1A)
    static let ink = dynamic(light: 0x111111, dark: 0xF2F2F2)
    /// The Reader's text that has not been read out yet (owner, 2026-09-12): `ink`, dimmed, so the
    /// page shows what is done and what is coming rather than tinting one paragraph at a time.
    static let inkUnread = dynamic(light: 0x111111, dark: 0xF2F2F2, lightAlpha: 0.28, darkAlpha: 0.34)
    static let ink2 = dynamic(light: 0x8A8A8A, dark: 0x8E8E8E)
    static let ink3 = dynamic(light: 0xC9C9C7, dark: 0x3A3A3A)
    static let accent = dynamic(light: 0xFF7A1A, dark: 0xFF8C3A)
    static let accentSoft = dynamic(light: 0xFF7A1A, dark: 0xFF8C3A, lightAlpha: 0.18, darkAlpha: 0.22)
    /// The sentence tint behind the active word (spec §2.4.5): the same accent, fainter.
    static let accentFaint = dynamic(light: 0xFF7A1A, dark: 0xFF8C3A, lightAlpha: 0.08, darkAlpha: 0.12)
    /// text on `accent`
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// The light of the voice warm-up (`WarmRamp`) and of the raised key (`RaisedButton`): blue,
    /// on the owner's word (2026-09-10, a blue CTA as the reference). Not `accent` — the accent is
    /// what the app marks *its own* things with (progress, the read-along, the one primary pill),
    /// and the glow is a state of the engine, not a mark on the page. Lighter in dark mode: the
    /// same blue on near-black reads as a dim navy.
    static let glow = dynamic(light: 0x2F5BFF, dark: 0x5F84FF)
    static let glowSoft = dynamic(light: 0x2F5BFF, dark: 0x5F84FF, lightAlpha: 0.18, darkAlpha: 0.24)
    static let glowFaint = dynamic(light: 0x2F5BFF, dark: 0x5F84FF, lightAlpha: 0.08, darkAlpha: 0.14)
    /// The last beat of the warm-up, when the voice is ready (owner, 2026-09-10: "just as the model
    /// is ready, change the glow to green before ending the animation"): the same light, green — a
    /// deeper green than `positive`, which is a tick on a row, not a light on the screen's edge.
    static let glowReady = dynamic(light: 0x12A150, dark: 0x37D97C)
    /// The raised key's face, lit from above: the reference's gradient, royal blue at the top rim
    /// falling to indigo at the foot. One object in both themes, like a book's cloth — a key does
    /// not change colour when the room does — but a touch lighter on black so its bevel still reads.
    static let keyTop = dynamic(light: 0x5477FF, dark: 0x5F81FF)
    static let keyBottom = dynamic(light: 0x2A1FE0, dark: 0x3226E8)
    /// The ink key — the bar at the foot of an Import step, the Voice page's "Make default", the
    /// Reader's skip pill — as a raised key (owner, 2026-09-10: "replace the black buttons with
    /// skeuomorphic versions"). Light: black, with a lighter top face. Dark: *not* the inversion
    /// `ink` would give (a white key on a black page was the one thing the owner was sure they did
    /// not want to decide on) but graphite — the same object in a dark room, lifted from `ground`
    /// by its lit top edge (`keyInkRim`) rather than by a shadow, which has nothing to fall on.
    /// Its foot is `surface`'s grey exactly, so it sits in the page's own family of greys.
    static let keyInkTop = dynamic(light: 0x333333, dark: 0x3E3E3E)
    static let keyInkBottom = dynamic(light: 0x0C0C0C, dark: 0x1E1E1E)
    /// The rim light on the ink key's top edge: strong in the dark, where it does the lifting.
    static let keyInkRim = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.30, darkAlpha: 0.42)
    /// Lettering on the ink key: the page's ground in light (white on black), and in the dark a
    /// white that is not the ground (the ground is black there).
    static let onKeyInk = dynamic(light: 0xF8F8F7, dark: 0xF4F4F2)
    /// A hairline round a surface that a shadow lifts in the light — the kind menu's card, the
    /// mini-player's capsule — so it keeps an edge in the dark, where a shadow on black is nothing.
    /// All but invisible in light; a faint light line in dark.
    static let edge = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.11)
    /// The favorite heart (`HeartButton`): a top-lit red, a shade lighter in the dark so it does
    /// not sink into the page.
    static let heartTop = dynamic(light: 0xFF6B6B, dark: 0xFF7A7A)
    static let heartBottom = dynamic(light: 0xDB1729, dark: 0xE62E3E)
    static let heartShade = dynamic(light: 0x99000D, dark: 0x000000)
    static let positive = dynamic(light: 0x22A559, dark: 0x34C070)
    static let destructive = dynamic(light: 0xE5453B, dark: 0xFF5A50)
    /// The voice picker's avatar discs: pink for a female voice, blue for a male one. Categorical,
    /// not accent — they say which of two kinds a row is, never that it is selected or active.
    static let voiceFemale = dynamic(light: 0xE8558A, dark: 0xF06E9E)
    static let voiceMale = dynamic(light: 0x3B82F6, dark: 0x5B9CFF)
    /// Lighting on artwork (`BookCover`): a shadow is dark and a highlight is light in both themes,
    /// unlike `ink`, which flips. Neither carries alpha — each use sets its own.
    static let shade = dynamic(light: 0x000000, dark: 0x000000)
    static let gloss = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// The PDF placeholder cover: a light red book that says PDF (owner's call, 2026-09-09).
    /// The "Default" tag in the voice list (owner, 2026-09-10: "light blue with dark blue text").
    static let tagBlue = dynamic(light: 0xDCEAFF, dark: 0x1B2D4A)
    static let tagBlueInk = dynamic(light: 0x1D4ED8, dark: 0x8AB4FF)
    static let pdfCover = dynamic(light: 0xF6D2CC, dark: 0x4A2521)
    static let pdfInk = dynamic(light: 0xB5362B, dark: 0xFF8E82)

    /// The generated covers' palette: eight cloth-binding colours a title is dealt from
    /// (`CoverStyle.paletteIndex`). A book is an object, so its colour is the same in both themes,
    /// like `shade` and `gloss`; the cream `coverText` sits on any of them. Each has a light tint
    /// for words on paper (`coverTint`, the sheet's masthead in dark mode) and a lifted glow for
    /// the book sheet's backlight.
    private static let coverPalette: [(ink: UInt32, tint: UInt32, glow: UInt32)] = [
        (0x2B4C5C, 0x8FB8CC, 0x7FB4CC),   // slate teal
        (0x7B3B3B, 0xD98A8A, 0xD98A8A),   // oxblood
        (0x35563F, 0x8FBF9C, 0x8FC4A0),   // forest
        (0x8A6B2E, 0xD9B45C, 0xE0B85C),   // ochre
        (0x4B3F6E, 0xB3A3E0, 0xB3A3E0),   // plum
        (0x9A5638, 0xE0967A, 0xE8997A),   // terracotta
        (0x3C4A78, 0x9DA9E6, 0x9DA9E6),   // indigo
        (0x5A5A52, 0xB5B5A8, 0xB5B5A8),   // charcoal olive
    ]
    static var coverCount: Int { coverPalette.count }
    /// The cloth of cover `index` (from `CoverStyle.paletteIndex(for:count: coverCount)`).
    static func coverInk(_ index: Int) -> Color {
        let ink = coverPalette[index % coverPalette.count].ink
        return dynamic(light: ink, dark: ink)
    }
    /// The same hue as words on paper: the cloth colour in light, its tint in dark.
    static func coverTint(_ index: Int) -> Color {
        let entry = coverPalette[index % coverPalette.count]
        return dynamic(light: entry.ink, dark: entry.tint)
    }
    /// The same hue as light: what a placeholder book gives off on the book sheet.
    static func coverGlow(_ index: Int) -> Color {
        let glow = coverPalette[index % coverPalette.count].glow
        return dynamic(light: glow, dark: glow)
    }
    /// Cream lettering on a generated cover, in both themes.
    static let coverText = dynamic(light: 0xF3EDE2, dark: 0xF3EDE2)
    /// The pasted-text sheet's paper and binding strip: a notepad's cream, so a text and a web page
    /// (on `raised`) never read as the same object.
    static let notePaper = dynamic(light: 0xFBF6E8, dark: 0x25221B)
    static let noteBinding = dynamic(light: 0xEFE6CF, dark: 0x332E22)

    /// The read-along pair is per `HighlightTheme`: a faint sentence tint and a stronger word mark in
    /// one hue. `amber` is the accent — `accentFaint` / `accentSoft` exactly — so it stays the default
    /// and a reader who never opens the picker sees nothing change.
    static func highlightTint(_ theme: HighlightTheme) -> Color {
        switch theme {
        case .amber: return accentFaint
        case .sky: return dynamic(light: 0x3B82F6, dark: 0x5B9CFF, lightAlpha: 0.10, darkAlpha: 0.14)
        case .fall: return dynamic(light: 0xB5562B, dark: 0xE0754A, lightAlpha: 0.10, darkAlpha: 0.14)
        case .marker: return dynamic(light: 0xEAB308, dark: 0xFACC15, lightAlpha: 0.16, darkAlpha: 0.14)
        case .mint: return dynamic(light: 0x10B981, dark: 0x34D399, lightAlpha: 0.10, darkAlpha: 0.14)
        }
    }

    /// The read-along word mark for a `HighlightTheme`: the same hue, stronger. `marker` is strongest —
    /// a yellow word mark is what reads as "highlighter".
    static func highlightWord(_ theme: HighlightTheme) -> Color {
        switch theme {
        case .amber: return accentSoft
        case .sky: return dynamic(light: 0x3B82F6, dark: 0x5B9CFF, lightAlpha: 0.28, darkAlpha: 0.34)
        case .fall: return dynamic(light: 0xB5562B, dark: 0xE0754A, lightAlpha: 0.30, darkAlpha: 0.36)
        case .marker: return dynamic(light: 0xEAB308, dark: 0xFACC15, lightAlpha: 0.48, darkAlpha: 0.42)
        case .mint: return dynamic(light: 0x10B981, dark: 0x34D399, lightAlpha: 0.28, darkAlpha: 0.34)
        }
    }

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
