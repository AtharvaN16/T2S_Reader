import Foundation
import T2SCore

/// The Reader page's text, drawn by us from the timeline (spec 2026-09-07 §3): paragraphs of the
/// utterances' own source text, chapter titles and headings, plus the answers the view needs —
/// where a highlight falls, what to tint, and which utterance a tap lands in. Every offset is
/// UTF-16 in the flattened string (`Paragraph.location` + an offset in `Paragraph.text`), the unit
/// `Utterance.source`, `HighlightRange.sourceRange` and `NSAttributedString` all count in.
public struct ReaderText: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case documentTitle
        case byline
        case chapterTitle
        case heading(level: Int)
        case body
    }

    /// One utterance inside a paragraph.
    public struct Span: Hashable, Sendable {
        public var utteranceIndex: Int
        /// UTF-16 range of the utterance's `source` inside the paragraph's `text`.
        public var range: Range<Int>

        public init(utteranceIndex: Int, range: Range<Int>) {
            self.utteranceIndex = utteranceIndex
            self.range = range
        }
    }

    public struct Paragraph: Hashable, Sendable, Identifiable {
        public var id: Int
        public var kind: Kind
        /// nil for the drawn title and byline.
        public var chapterIndex: Int?
        public var text: String
        /// Where `text` starts in the flattened string.
        public var location: Int
        /// The utterances this paragraph holds, in order; empty for text that is never spoken.
        public var spans: [Span]
        /// False on a PDF page: the tinted unit there is the utterance, not the page.
        public var tintsWholeParagraph: Bool

        public var range: Range<Int> { location ..< location + text.utf16.count }
    }

    public let documentID: UUID
    public private(set) var paragraphs: [Paragraph]
    /// UTF-16 length of the flattened string: paragraph texts joined by "\n".
    public private(set) var length: Int
    private var paragraphByUtterance: [Int]
    private var spanByUtterance: [Int]

    private struct BlockKey: Equatable {
        var href: String
        var selector: String?
        /// The page, for a PDF (no selector).
        var progression: Double?

        init(_ position: Position) {
            href = position.resourceHref
            selector = position.cssSelector
            progression = position.cssSelector == nil ? position.progression : nil
        }
    }

    private struct Item {
        var kind: Kind
        var chapter: Int?
        var text: String
        var spans: [Span]
        var tintsWhole: Bool
    }

    public init(documentID: UUID, timeline: Timeline, title: String, author: String?) {
        self.documentID = documentID
        var items: [Item] = []
        let documentTitle = Self.normalized(title)
        var utteranceIndex = 0
        for (c, chapter) in timeline.chapters.enumerated() {
            // Consecutive utterances that share a block, in order.
            var blocks: [[(index: Int, utterance: Utterance)]] = []
            var keys: [BlockKey] = []
            for utterance in chapter.utterances {
                let key = BlockKey(utterance.position)
                if keys.last == key {
                    blocks[blocks.count - 1].append((utteranceIndex, utterance))
                } else {
                    keys.append(key)
                    blocks.append([(utteranceIndex, utterance)])
                }
                utteranceIndex += 1
            }
            let chapterTitle = Self.normalized(chapter.title)
            for (b, block) in blocks.enumerated() {
                var text = ""
                var spans: [Span] = []
                for (index, utterance) in block {
                    if !text.isEmpty { text += " " }
                    let start = text.utf16.count
                    text += Self.displayText(utterance.source)
                    spans.append(Span(utteranceIndex: index, range: start ..< text.utf16.count))
                }
                let selector = block[0].utterance.position.cssSelector
                var kind = Self.kind(forSelector: selector)
                if b == 0 {
                    if Self.normalized(text) == chapterTitle {
                        kind = .chapterTitle
                    } else if chapterTitle != documentTitle {
                        items.append(Item(kind: .chapterTitle, chapter: c, text: chapter.title, spans: [], tintsWhole: true))
                    }
                }
                items.append(Item(kind: kind, chapter: c, text: text, spans: spans, tintsWhole: selector != nil))
            }
        }

        // The title at the top: the first spoken paragraph when it says the title, else drawn and
        // never spoken. The byline follows it.
        if let first = items.firstIndex(where: { !$0.spans.isEmpty }), Self.normalized(items[first].text) == documentTitle {
            var spokenTitle = items.remove(at: first)
            spokenTitle.kind = .documentTitle
            items.insert(spokenTitle, at: 0)
        } else {
            items.insert(Item(kind: .documentTitle, chapter: nil, text: title, spans: [], tintsWhole: true), at: 0)
        }
        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            items.insert(Item(kind: .byline, chapter: nil, text: author, spans: [], tintsWhole: true), at: 1)
        }

        var paragraphs: [Paragraph] = []
        var location = 0
        var paragraphByUtterance = Array(repeating: -1, count: timeline.utteranceCount)
        var spanByUtterance = Array(repeating: -1, count: timeline.utteranceCount)
        for item in items {
            let id = paragraphs.count
            paragraphs.append(Paragraph(id: id, kind: item.kind, chapterIndex: item.chapter, text: item.text,
                                        location: location, spans: item.spans, tintsWholeParagraph: item.tintsWhole))
            for (s, span) in item.spans.enumerated() {
                paragraphByUtterance[span.utteranceIndex] = id
                spanByUtterance[span.utteranceIndex] = s
            }
            location += item.text.utf16.count + 1
        }
        self.paragraphs = paragraphs
        self.length = max(0, location - 1)
        self.paragraphByUtterance = paragraphByUtterance
        self.spanByUtterance = spanByUtterance
    }

    // MARK: Queries

    public func paragraphIndex(forUtterance i: Int) -> Int? {
        guard paragraphByUtterance.indices.contains(i), paragraphByUtterance[i] >= 0 else { return nil }
        return paragraphByUtterance[i]
    }

    private func span(forUtterance i: Int) -> (paragraph: Paragraph, span: Span)? {
        guard let p = paragraphIndex(forUtterance: i) else { return nil }
        return (paragraphs[p], paragraphs[p].spans[spanByUtterance[i]])
    }

    /// The paragraph containing a flattened-string offset (the "\n" after a paragraph counts as its own).
    public func paragraph(at offset: Int) -> Paragraph? {
        guard offset >= 0, offset <= length, !paragraphs.isEmpty else { return nil }
        var low = 0
        var high = paragraphs.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if paragraphs[mid].location <= offset { low = mid } else { high = mid - 1 }
        }
        return paragraphs[low]
    }

    /// The highlight's `sourceRange` shifted into the document; nil when it falls outside its utterance.
    public func wordRange(for highlight: HighlightRange) -> Range<Int>? {
        guard let located = span(forUtterance: highlight.utteranceIndex),
              highlight.sourceRange.lowerBound >= 0,
              highlight.sourceRange.upperBound <= located.span.range.count
        else { return nil }
        let base = located.paragraph.location + located.span.range.lowerBound
        return (base + highlight.sourceRange.lowerBound) ..< (base + highlight.sourceRange.upperBound)
    }

    /// The whole paragraph, or the utterance's own range on a PDF page.
    public func tintRange(forUtterance i: Int) -> Range<Int>? {
        guard let located = span(forUtterance: i) else { return nil }
        let (paragraph, span) = located
        if paragraph.tintsWholeParagraph { return paragraph.range }
        return (paragraph.location + span.range.lowerBound) ..< (paragraph.location + span.range.upperBound)
    }

    /// The utterance under a flattened-string offset and the offset inside its `source`. An offset in
    /// the gap between two spans belongs to the next utterance (start); the paragraph's end belongs
    /// to the last utterance's last character; nil in text that is never spoken or past the end.
    public func hit(at offset: Int) -> (utteranceIndex: Int, sourceOffset: Int)? {
        guard let paragraph = paragraph(at: offset), let last = paragraph.spans.last else { return nil }
        let local = offset - paragraph.location
        if let inside = paragraph.spans.first(where: { $0.range.contains(local) }) {
            return (inside.utteranceIndex, local - inside.range.lowerBound)
        }
        if let next = paragraph.spans.first(where: { $0.range.lowerBound > local }) {
            return (next.utteranceIndex, 0)
        }
        return (last.utteranceIndex, max(0, last.range.count - 1))
    }

    // MARK: Rules

    /// A block's kind from its selector: the tag at the start of the last `>` segment, when it is h1…h6.
    /// An `#id` segment says nothing about the tag, so those blocks stay body (Readium 3.11 labels
    /// every text element `.body`; the selector is the only signal).
    static func kind(forSelector selector: String?) -> Kind {
        guard let selector else { return .body }
        let last = selector.split(separator: ">").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let tag = last.prefix { $0.isLetter || $0.isNumber }.lowercased()
        guard tag.count == 2, tag.hasPrefix("h"), let level = Int(String(tag.suffix(1))), (1...6).contains(level) else {
            return .body
        }
        return .heading(level: level)
    }

    /// The source with every whitespace scalar shown as a space; the UTF-16 length never changes, so
    /// offsets into `source` and into the paragraph are the same numbers (spec 2026-09-07 §3).
    public static func displayText(_ source: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in source.unicodeScalars {
            scalars.append(scalar.properties.isWhitespace ? " " : scalar)
        }
        return String(scalars)
    }

    /// Whitespace collapsed, case folded, trailing `.:;` and whitespace removed — how a block's text is
    /// compared with a chapter or document title.
    public static func normalized(_ s: String) -> String {
        let collapsed = s.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        var trimmed = Substring(collapsed)
        while let last = trimmed.last, last.isWhitespace || ".:;".contains(last) { trimmed = trimmed.dropLast() }
        return String(trimmed)
    }
}
