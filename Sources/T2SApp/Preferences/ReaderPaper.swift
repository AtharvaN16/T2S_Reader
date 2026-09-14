import Foundation

/// The paper the Reader draws its page on (owner, 2026-09-14; the palette is
/// `docs/design/2026-09-14-reader-papers-16.html`). Sixteen of them in two families: eight quiet
/// ones to read a book on, eight loud ones to read a chapter on.
///
/// A paper is a *hue*, not a time of day. Each has a lit and an unlit face and the device's trait
/// picks between them, so choosing Sky does not mean choosing daylight — the app-wide theme still
/// owns that, and still owns every screen that is not the Reader.
public enum ReaderPaper: String, CaseIterable, Sendable, Hashable {
    // Zen — a tint, which a page can wear while still hosting the app's own colours.
    case paper, sepia, rose, lilac, sky, mint, sage, honey
    // Pop — the page *is* the colour, and so it cannot host four more: see `ReaderPalette`'s
    // pop rule, where the chrome is drawn from the paper's own ink instead.
    case mono, cherry, tangerine, sunflower, lime, cobalt, violet, magenta

    public enum Family: Sendable { case zen, pop }

    public var family: Family {
        switch self {
        case .paper, .sepia, .rose, .lilac, .sky, .mint, .sage, .honey: return .zen
        case .mono, .cherry, .tangerine, .sunflower, .lime, .cobalt, .violet, .magenta: return .pop
        }
    }

    public var title: String { rawValue.capitalized }

    public static func all(_ family: Family) -> [ReaderPaper] {
        allCases.filter { $0.family == family }
    }
}
