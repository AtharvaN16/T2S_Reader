import Foundation
import Testing
@testable import T2SKokoro

@Suite struct KokoroTokenizerTests {
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles))
    func tokenizesEveryVocabSymbolAndDropsUnknowns() throws {
        let located = try KokoroCoreMLResources.locate(inDirectory: KokoroCoreMLResources.developmentDirectory).get()
        let voiceURL = try #require(located.voices["af_heart"])
        let t = try KokoroTokenizer(vocabURL: located.vocab, voiceURL: voiceURL)

        let r = t.tokenize(phonemes: "hˈɛlO wˈɜɹld❓", ownersByCharacter: Array(repeating: 0, count: 13))
        #expect(r.dropped == 1 && r.ids.count == 12 && r.owners.count == 12)
        #expect(t.refS(phonemeUTF16Count: 5).count == 256 && t.refS(phonemeUTF16Count: 10_000) == t.refS(phonemeUTF16Count: t.voiceRowCount))
    }
}
