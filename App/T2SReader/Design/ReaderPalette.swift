// App/T2SReader/Design/ReaderPalette.swift
import SwiftUI
import T2SApp
import UIKit

/// What a `ReaderPaper` actually paints (palette: `docs/design/2026-09-14-reader-papers-16.html`).
///
/// This is `Tokens` for one screen. The Reader page and its own chrome read it; nothing else in the
/// app does, which is the whole of "the theme applies to the Reader only" — no other screen can be
/// surprised by a paper, because no other screen can see one.
///
/// Every value but the two ends is derived by mixing ink into paper, so a paper is two hex numbers
/// per face and the rest follows. That is not laziness: it is what keeps sixteen papers coherent —
/// a hairline is always the same distance from the page it sits on, whichever page that is.
///
/// **The pop rule.** A zen paper is a tint and can host the app's colours, so it keeps them: the
/// blue key, the accent playhead, the read-along in the hue this paper pins for it. A pop paper
/// *is* a colour, and a page that is a colour cannot host four more — a blue key on Cobalt is an
/// object hiding inside its own background. So a pop paper draws its chrome from its own ink and
/// paper and borrows nothing (owner's design review, 2026-09-14).
struct ReaderPalette: Equatable {
    /// Which paper this is. Identity, for the views that cache by it — the text view re-typesets
    /// its whole string when this changes, and nothing else about a palette can change without it.
    var paper: ReaderPaper
    /// The page itself.
    var page: Color
    /// What a sheet over the page stands on. A paper's sheets are the paper — the chapter list and
    /// the timer belong to the book being read, not to the app around it (owner, 2026-09-14) — and
    /// the app's own `raised` everywhere else.
    var sheet: Color
    /// Body text: the sentences already spoken.
    var ink: Color
    /// Secondary lettering — the clocks, the chapter name, a label.
    var ink2: Color
    /// Hairlines and the unplayed part of a bar.
    var ink3: Color
    /// The discs the Reader's glyphs sit on.
    var surface: Color
    /// The text ahead of the playhead.
    var unread: Color
    /// The sentence being spoken, and the word inside it.
    var wash: Color
    var mark: Color
    /// The playhead, the render frontier: `accent` on a zen paper, the paper's own ink on a pop one.
    var accent: Color
    /// A delete, where the Reader draws one.
    var destructive: Color
    /// A chapter already heard, a thing that finished.
    var positive: Color
    /// True when the chrome must come from the paper rather than from `Tokens`.
    var isPop: Bool

    static let `default` = ReaderPalette(.paper)

    init(_ paper: ReaderPaper) {
        self.paper = paper
        let face = Self.faces[paper] ?? Self.faces[.paper]!
        let pop = paper.family == .pop
        func mixed(_ t: Double) -> Color {
            Self.dynamic(light: Self.mix(face.lightInk, face.lightPage, t),
                         dark: Self.mix(face.darkInk, face.darkPage, t))
        }
        page = Self.dynamic(light: face.lightPage, dark: face.darkPage)
        sheet = Self.dynamic(light: face.lightPage, dark: face.darkPage)
        ink = Self.dynamic(light: face.lightInk, dark: face.darkInk)
        ink2 = mixed(0.52)
        ink3 = mixed(0.16)
        surface = mixed(0.10)
        // The unlit face carries a touch more, because a dim grey on black falls away faster than
        // the same grey on paper does.
        unread = Self.dynamic(light: Self.mix(face.lightInk, face.lightPage, 0.30),
                              dark: Self.mix(face.darkInk, face.darkPage, 0.34))
        isPop = pop
        if pop {
            wash = mixed(0.12)
            mark = mixed(0.26)
            accent = mixed(0.70)
            destructive = Self.dynamic(light: face.lightInk, dark: face.darkInk)
            positive = mixed(0.70)
        } else {
            // Rule C: the read-along is an 8%-alpha wash, so on paper of its own hue it simply is
            // not there. Each zen paper pins a highlight at least 60° of hue away from itself.
            wash = Tokens.highlightTint(Self.highlight[paper] ?? .amber)
            mark = Tokens.highlightWord(Self.highlight[paper] ?? .amber)
            accent = Tokens.accent
            destructive = Tokens.destructive
            positive = Tokens.positive
        }
    }

    /// The app's own greys, worn as a palette. This is what every shared view gets when it is not
    /// standing in the Reader — the Book sheet's copy of the chapter list, the sleep timer opened
    /// from Home — so a paper cannot leak out of the one screen that chose it.
    static let app: ReaderPalette = {
        var p = ReaderPalette(.paper)
        p.page = Tokens.ground
        p.sheet = Tokens.raised
        p.ink = Tokens.ink
        p.ink2 = Tokens.ink2
        p.ink3 = Tokens.ink3
        p.surface = Tokens.surface
        p.unread = Tokens.inkUnread
        return p
    }()

    /// The read-along hue each zen paper pins. Not the reader's choice any more — the picker for it
    /// went on 2026-09-12, and a paper knows better than a menu which tint will show on it.
    private static let highlight: [ReaderPaper: HighlightTheme] = [
        .paper: .amber, .sepia: .sky, .rose: .sky, .lilac: .amber,
        .sky: .amber, .mint: .fall, .sage: .marker, .honey: .sky,
    ]

    static func == (a: ReaderPalette, b: ReaderPalette) -> Bool { a.paper == b.paper }

    private struct Face {
        var lightPage: UInt32, lightInk: UInt32, darkPage: UInt32, darkInk: UInt32
    }

    /// Page and ink, lit and unlit. The inks of the vivid pop papers are pure black on purpose:
    /// each was lightened in the palette study until black cleared 7:1 on it, which is what makes
    /// Cherry, Cobalt and Violet readable rather than a dare.
    private static let faces: [ReaderPaper: Face] = [
        .paper:     Face(lightPage: 0xF8F8F7, lightInk: 0x111111, darkPage: 0x101010, darkInk: 0xF2F2F2),
        .sepia:     Face(lightPage: 0xF4ECDB, lightInk: 0x2A2118, darkPage: 0x17120C, darkInk: 0xEFE6D8),
        .rose:      Face(lightPage: 0xFBECEA, lightInk: 0x2E1C1A, darkPage: 0x1A0F10, darkInk: 0xF4E7E6),
        .lilac:     Face(lightPage: 0xF2EDFA, lightInk: 0x221B2E, darkPage: 0x150F1C, darkInk: 0xEDE4F5),
        .sky:       Face(lightPage: 0xEBF1FA, lightInk: 0x16202C, darkPage: 0x0D121B, darkInk: 0xE7EDF7),
        .mint:      Face(lightPage: 0xE9F4F0, lightInk: 0x13231E, darkPage: 0x0C1917, darkInk: 0xDFEFEA),
        .sage:      Face(lightPage: 0xEDF3EB, lightInk: 0x17241A, darkPage: 0x0D140F, darkInk: 0xE5EFE6),
        .honey:     Face(lightPage: 0xFAF2DA, lightInk: 0x2A2413, darkPage: 0x191307, darkInk: 0xF3E9D2),
        .mono:      Face(lightPage: 0xFFFFFF, lightInk: 0x000000, darkPage: 0x000000, darkInk: 0xFFFFFF),
        .cherry:    Face(lightPage: 0xFF6B60, lightInk: 0x000000, darkPage: 0x2A0806, darkInk: 0xFFE9E6),
        .tangerine: Face(lightPage: 0xFF8A1F, lightInk: 0x1F0C00, darkPage: 0x2B1403, darkInk: 0xFFEEDD),
        .sunflower: Face(lightPage: 0xFFD028, lightInk: 0x332700, darkPage: 0x2A2102, darkInk: 0xFFF4D6),
        .lime:      Face(lightPage: 0x7BE84F, lightInk: 0x0C2A06, darkPage: 0x0E2408, darkInk: 0xE9FBE0),
        .cobalt:    Face(lightPage: 0x5D97FF, lightInk: 0x000000, darkPage: 0x061630, darkInk: 0xE2ECFF),
        .violet:    Face(lightPage: 0xB184FF, lightInk: 0x000000, darkPage: 0x180A33, darkInk: 0xF0E6FF),
        .magenta:   Face(lightPage: 0xFF5FC0, lightInk: 0x000000, darkPage: 0x300824, darkInk: 0xFFE4F5),
    ]

    /// `t` of `a` over `b`, channel by channel in sRGB. Good enough for greys of one hue, which is
    /// all this mixes: both ends of every mix here are the same paper's own two colours.
    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        var out: UInt32 = 0
        for shift in [16, 8, 0] {
            let ca = Double((a >> UInt32(shift)) & 0xFF), cb = Double((b >> UInt32(shift)) & 0xFF)
            out |= UInt32((ca * t + cb * (1 - t)).rounded()) << UInt32(shift)
        }
        return out
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark, alpha: 1) : UIColor(rgb: light, alpha: 1) })
    }

    /// The two faces as flat colours, for the picker's split swatch — which has to show both at
    /// once, and so cannot ask the trait which one it is in.
    static func swatch(_ paper: ReaderPaper) -> (light: Color, dark: Color, lightInk: Color, darkInk: Color) {
        let face = faces[paper] ?? faces[.paper]!
        func flat(_ hex: UInt32) -> Color { Color(UIColor(rgb: hex, alpha: 1)) }
        return (flat(face.lightPage), flat(face.darkPage), flat(face.lightInk), flat(face.darkInk))
    }
}

private struct ReaderPaletteKey: EnvironmentKey {
    /// The app's greys, not Paper: outside the Reader nothing has chosen a paper, and the shared
    /// views must look exactly as they always have.
    static let defaultValue = ReaderPalette.app
}

extension EnvironmentValues {
    /// The Reader's paper, for the page and its own chrome. Everywhere else this is `Paper` — the
    /// app's own greys — because everywhere else is not the Reader.
    var readerPalette: ReaderPalette {
        get { self[ReaderPaletteKey.self] }
        set { self[ReaderPaletteKey.self] = newValue }
    }
}
