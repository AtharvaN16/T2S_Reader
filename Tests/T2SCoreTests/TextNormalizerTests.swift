import Foundation
import Testing
@testable import T2SCore

@Suite struct TextNormalizerTests {
    @Test func appliesRulesInSpecOrder() {
        let n = TextNormalizer(dictionary: [PronunciationEntry(term: "Doctor", replacement: "Dokter")])
        let t = n.normalize("Dr. Smith [1] paid $5 on\nhttps://x.com/a  in 1999.")
        #expect(t.spoken == "Dokter Smith paid five dollars on x.com in nineteen ninety-nine.")
        expectEveryWordMapsToSource(t)
    }

    @Test func versionMatchesVersions() {
        #expect(TextNormalizer.version == Versions.normalizer)
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
