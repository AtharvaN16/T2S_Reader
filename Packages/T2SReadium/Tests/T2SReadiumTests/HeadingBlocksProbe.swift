import Foundation
import Testing
import T2SCore
import T2SLibrary
@testable import T2SReadium

/// What a real book's chapter headings become — the blocks a reader extracts and the utterances the
/// builder makes of them — printed for a person to read. Written for the owner's report of
/// 2026-09-16, where a heading set as `<h2>3<br/>AN UNEASY EQUILIBRIUM</h2>` left the number a
/// one-word utterance (`spikes/findings/2026-09-16-lone-chapter-numbers.md`).
///
/// Not a test: point `T2S_PROBE_EPUB` at an EPUB to run it. The simulator shares the Mac's
/// filesystem, so an absolute path to a book on the Mac works.
@Suite struct HeadingBlocksProbe {
    static let bookPath = ProcessInfo.processInfo.environment["T2S_PROBE_EPUB"] ?? ""

    @Test(.enabled(if: !HeadingBlocksProbe.bookPath.isEmpty
        && FileManager.default.fileExists(atPath: HeadingBlocksProbe.bookPath)))
    func dumpsHeadingUtterances() async throws {
        let read = try await ReadiumDocumentReader().read(fileURL: URL(fileURLWithPath: Self.bookPath), sourceType: .epub)
        let timeline = TimelineBuilder.build(chapters: read.chapters,
                                             segmenter: Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength))
        for chapter in timeline.chapters {
            print("PROBE ---- chapter \(chapter.title.debugDescription)")
            for utterance in chapter.utterances.prefix(2) {
                print("PROBE   source=\(utterance.source.prefix(70).debugDescription)")
                print("PROBE   spoken=\(utterance.spoken.prefix(70).debugDescription) off=\(utterance.position.charOffset.map(String.init) ?? "nil")")
            }
        }
    }
}
