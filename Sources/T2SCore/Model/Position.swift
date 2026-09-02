/// Persisted anchor into the source document. Never a Readium type (spec §3.7.2).
public struct Position: Codable, Hashable, Sendable {
    public var resourceHref: String
    /// 0…1 within the resource.
    public var progression: Double
    /// UTF-16 offset into the resource's extracted text, when known.
    public var charOffset: Int?
    public var cssSelector: String?

    public init(resourceHref: String, progression: Double, charOffset: Int? = nil, cssSelector: String? = nil) {
        self.resourceHref = resourceHref
        self.progression = progression
        self.charOffset = charOffset
        self.cssSelector = cssSelector
    }
}
