/// Phase 1 of spec §3.3: every utterance with a Position and an estimated duration, no audio.
public enum TimelineBuilder {
    public static func build(chapters: [ChapterInput], segmenter: Segmenter) -> Timeline {
        Timeline(
            chapters: chapters.map { input in
                Chapter(title: input.title,
                        position: input.position,
                        utterances: joined(input.blocks).flatMap(segmenter.segment))
            },
            schemaVersion: Versions.schema,
            segmenterVersion: Segmenter.version,
            normalizerVersion: TextNormalizer.version
        )
    }

    /// Consecutive blocks that a reader cut out of one source element, put back together.
    ///
    /// Readium's content iterator ends a text element at every `<br/>`, so a chapter heading written
    /// `<h2>3<br/>AN UNEASY EQUILIBRIUM</h2>` arrives as two blocks. Segmenting per block, the number
    /// becomes a synthesis call of one word, and Kokoro reads a one-word call far above the voice's
    /// own narration pitch — up to an octave on some voices, which is what the owner heard as "it
    /// says three in a very high-pitched sound" (`spikes/findings/2026-09-16-lone-chapter-numbers.md`).
    ///
    /// Two blocks join only when they really are one element's text: same resource, same CSS
    /// selector (the iterator takes it from the enclosing element, so the pieces of one `<h2>` share
    /// it while two paragraphs never do), and adjacent in the extracted text — the readers count
    /// `charOffset` over trimmed block texts joined by a newline, so `next == offset + length + 1`
    /// is exactly "nothing between them", and the newline this inserts is the one that was already
    /// counted. Everything else is left alone: a short paragraph of dialogue keeps its own pause and
    /// its own highlight, and a PDF block, which carries no selector, never joins at all.
    static func joined(_ blocks: [SourceBlock]) -> [SourceBlock] {
        var result: [SourceBlock] = []
        for block in blocks {
            if var last = result.last, follows(block, last) {
                last.text += "\n" + block.text
                result[result.count - 1] = last
            } else {
                result.append(block)
            }
        }
        return result
    }

    /// Whether `block` is the rest of `previous`'s element, with nothing in the extracted text
    /// between them.
    private static func follows(_ block: SourceBlock, _ previous: SourceBlock) -> Bool {
        guard let selector = previous.position.cssSelector, block.position.cssSelector == selector,
              block.position.resourceHref == previous.position.resourceHref,
              let start = previous.position.charOffset, let next = block.position.charOffset
        else { return false }
        return next == start + previous.text.utf16.count + 1
    }
}
