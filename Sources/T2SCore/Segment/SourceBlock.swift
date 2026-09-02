public struct SourceBlock: Hashable, Sendable {
    public var text: String
    /// `charOffset` is the UTF-16 offset of this block within its resource's extracted text.
    public var position: Position

    public init(text: String, position: Position) {
        self.text = text
        self.position = position
    }
}

public struct ChapterInput: Hashable, Sendable {
    public var title: String
    public var position: Position
    public var blocks: [SourceBlock]

    public init(title: String, position: Position, blocks: [SourceBlock]) {
        self.title = title
        self.position = position
        self.blocks = blocks
    }
}
