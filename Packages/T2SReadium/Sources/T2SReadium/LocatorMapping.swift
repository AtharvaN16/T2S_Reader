import Foundation
import ReadiumShared
import T2SCore

/// The Readium boundary (spec §3.7.2): `Position` in, `Locator` out, and back. A word highlight is
/// a text quote with context plus the block's CSS selector, which the EPUB navigator's decorator
/// resolves to a DOM range.
public enum LocatorMapping {
    /// UTF-16 units of context on each side of a highlight quote.
    public static let contextLength = 50

    public static func locator(for position: Position, mediaType: MediaType = .xhtml, text: Locator.Text = Locator.Text()) -> Locator? {
        guard let href = AnyURL(string: position.resourceHref) else { return nil }
        var locations = Locator.Locations(progression: position.progression)
        if let selector = position.cssSelector { locations.otherLocations["cssSelector"] = .string(selector) }
        return Locator(href: href, mediaType: mediaType, locations: locations, text: text)
    }

    /// The persisted form of a navigator locator (a tapped sentence, the visible page). `charOffset`
    /// is unknown here; `PositionResolver` falls back to progression within the resource.
    /// `resourceHref` is normalized through `ReadiumDocumentReader.resourceKey` — the same key the
    /// content iterator persists — so a position from either Readium API compares equal by resource.
    public static func position(for locator: Locator) -> Position {
        var selector: String?
        if case .string(let s)? = locator.locations.otherLocations["cssSelector"] { selector = s }
        return Position(resourceHref: ReadiumDocumentReader.resourceKey(locator.href.string),
                        progression: locator.locations.progression ?? 0, charOffset: nil, cssSelector: selector)
    }

    /// The active word: the utterance's source slice as the quote, with up to `contextLength` UTF-16
    /// units of the same utterance before and after it.
    public static func locator(for range: HighlightRange, in timeline: Timeline, mediaType: MediaType = .xhtml) -> Locator? {
        guard range.utteranceIndex >= 0, range.utteranceIndex < timeline.utteranceCount else { return nil }
        let source = timeline[utterance: range.utteranceIndex].source as NSString
        let quote = NSRange(location: range.sourceRange.lowerBound, length: range.sourceRange.count)
        guard quote.location >= 0, quote.location + quote.length <= source.length else { return nil }
        let beforeStart = max(0, quote.location - contextLength)
        let afterEnd = min(source.length, quote.location + quote.length + contextLength)
        let afterStart = quote.location + quote.length
        let text = Locator.Text(
            after: afterStart < afterEnd ? source.substring(with: NSRange(location: afterStart, length: afterEnd - afterStart)) : nil,
            before: beforeStart < quote.location ? source.substring(with: NSRange(location: beforeStart, length: quote.location - beforeStart)) : nil,
            highlight: source.substring(with: quote))
        return locator(for: range.position, mediaType: mediaType, text: text)
    }
}
