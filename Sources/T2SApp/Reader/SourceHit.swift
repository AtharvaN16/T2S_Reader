import Foundation

/// What a tap on the page reports: the resource, the tapped block's text, and the UTF-16 caret
/// offset inside it. PDF taps carry only the page (spec §6.1: page-level sync).
public struct SourceHit: Hashable, Sendable {
    /// The normalized resource key, as persisted in `Position.resourceHref`.
    public var resourceHref: String
    public var blockText: String
    public var offsetInBlock: Int
    public var pageIndex: Int?

    public init(resourceHref: String, blockText: String, offsetInBlock: Int, pageIndex: Int? = nil) {
        self.resourceHref = resourceHref
        self.blockText = blockText
        self.offsetInBlock = offsetInBlock
        self.pageIndex = pageIndex
    }
}
