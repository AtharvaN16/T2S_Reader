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
    static let titleTop: CGFloat = 56
    static let sheetCorner: CGFloat = 28
    static let artworkSmall: CGFloat = 8
    /// Trailing space on the root pages so their last row scrolls clear of the bottom bar's fill
    /// (`RootPager.bottomFill`: 180 pt of fade over the page row's 40 pt and a 34 pt home-indicator
    /// inset, measured from the screen bottom, less the row's own 28 pt gap).
    static let bottomClearance: CGFloat = 232
}
