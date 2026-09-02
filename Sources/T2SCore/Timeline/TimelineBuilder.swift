/// Phase 1 of spec §3.3: every utterance with a Position and an estimated duration, no audio.
public enum TimelineBuilder {
    public static func build(chapters: [ChapterInput], segmenter: Segmenter) -> Timeline {
        Timeline(
            chapters: chapters.map { input in
                Chapter(title: input.title,
                        position: input.position,
                        utterances: input.blocks.flatMap(segmenter.segment))
            },
            schemaVersion: Versions.schema,
            segmenterVersion: Segmenter.version,
            normalizerVersion: TextNormalizer.version
        )
    }
}
