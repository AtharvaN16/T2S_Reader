// App/T2SReader/Design/Spacing.swift
import CoreGraphics

/// Spec §2.4.3. Rhythm comes from white space and type weight, never from cards or dividers.
enum Spacing {
    static let grid: CGFloat = 8
    static let margin: CGFloat = 24
    static let row: CGFloat = 28
    /// The gap between one Home book and the next (owner, 2026-09-11: more air than the shared
    /// `row` rhythm) — a row now carries its own Play pill, and the tighter general list gap read
    /// as cramped between one book's pill and the next book's cover.
    static let homeRowGap: CGFloat = 40
    static let section: CGFloat = 40
    /// 40 since 2026-09-12 (owner: "the page starts slightly higher on every page"). It was 56,
    /// which was not a rhythm so much as a clearance: the warm-up's three rows reach `inset + 54`
    /// and 56 was the smallest number that kept a page title out from under them. `TopFade` holds
    /// that clearance now — it grows its own ground to `WarmUpLine.bandHeight` while the glow is up
    /// — so the title is free to sit where it looks right rather than where the warm-up allows.
    static let titleTop: CGFloat = 40
    /// Where a *pushed* page's title sits, which cannot be `titleTop`: a Settings subpage draws its
    /// own way back as a 36 pt circle at 12 from the top, so the circle reaches 48 and a title at 40
    /// runs into its foot (owner, 2026-09-15: "their header is way too close to the back button").
    /// This clears it by 16 — the same air the circle has above it — so the two read as a row and a
    /// title rather than as two things that collided.
    static let subpageTitleTop: CGFloat = 64
    static let sheetCorner: CGFloat = 28
    static let artworkSmall: CGFloat = 8
    /// Trailing space on the root pages so their last row scrolls clear of the bottom bar's fill
    /// (`RootPager.bottomFill`: 180 pt of fade over the page row's 40 pt and a 34 pt home-indicator
    /// inset, measured from the screen bottom, less the row's own 28 pt gap).
    static let bottomClearance: CGFloat = 232
}
