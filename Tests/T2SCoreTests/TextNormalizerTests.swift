import Foundation
import Testing
@testable import T2SCore

@Suite struct TextNormalizerTests {
    @Test func appliesRulesInSpecOrder() {
        let n = TextNormalizer(dictionary: [PronunciationEntry(term: "Doctor", replacement: "Dokter")])
        let t = n.normalize("Dr. Smith [1] paid $5 on\nhttps://x.com/a  in 1999.")
        #expect(t.spoken == "Dokter Smith paid five dollars on x.com in nineteen ninety nine.")
        expectEveryWordMapsToSource(t)
    }

    @Test func versionMatchesVersions() {
        #expect(TextNormalizer.version == Versions.normalizer)
    }

    /// The footnote number goes before the number rule can spell it out.
    @Test func neverSpeaksAFootnoteNumber() {
        let t = TextNormalizer().normalize("of the elite quarter of Daryaganj.14 The presence of sepoys billeted above.")
        #expect(t.spoken == "of the elite quarter of Daryaganj. The presence of sepoys billeted above.")
        expectEveryWordMapsToSource(t)
    }

    /// Rule 1 keeps a real hyphen; the pipeline still speaks it as a word break, after URLs are
    /// collapsed (a host keeps its hyphen long enough to be recognised) and before numbers expand.
    @Test func speaksHyphenatedCompoundsAsSeparateWords() {
        let t = TextNormalizer().normalize("The well-known site https://foo-bar.com/x opened in mid-1990s style.")
        #expect(t.spoken == "The well known site foo bar.com opened in mid nineteen nineties style.")
        expectEveryWordMapsToSource(t)
    }

    @Test(arguments: [
        ("see https://www.nytimes.com/2024/05/01/tech.html today", "see nytimes.com today"),
        ("cite https://doi.org/10.1038/s41586-021-03819-2 now.", "cite doi.org now."),
        ("[1] The opening citation.", "The opening citation."),
    ])
    func pipelineKeepsURLsAndTrimsLeadingCitations(input: String, expected: String) {
        let t = TextNormalizer().normalize(input)
        #expect(t.spoken == expected)
        expectEveryWordMapsToSource(t)
    }

    @Test func everyWordInCorpusMapsToSource() throws {
        let url = try #require(Bundle.module.url(forResource: "corpus", withExtension: "txt", subdirectory: "Fixtures"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.count >= 40)
        let n = TextNormalizer()
        for line in lines {
            let t = n.normalize(line)
            #expect(!t.spoken.isEmpty, "\(line)")
            expectEveryWordMapsToSource(t)
        }
    }
}
