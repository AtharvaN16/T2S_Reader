import Foundation
import Testing
@testable import T2SCore

@Suite struct RenderKeyTests {
    let doc = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    func key(index: Int = 3, voice: String = "af_heart", engine: String = "kokoro", norm: Int = 1, seg: Int = 1) -> RenderKey {
        RenderKey(documentID: doc, utteranceIndex: index, voiceID: voice, engineID: engine, normalizerVersion: norm, segmenterVersion: seg)
    }

    @Test func deterministic() {
        #expect(key() == key())
        #expect(key().rawValue.count == 64)
        #expect(key().rawValue.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(key().fileName == key().rawValue + ".audio")
    }

    @Test func everyInputChangesTheKey() {
        let base = key()
        #expect(key(index: 4) != base)
        #expect(key(voice: "am_adam") != base)
        #expect(key(engine: "http") != base)
        #expect(key(norm: 2) != base)
        #expect(key(seg: 2) != base)
        #expect(RenderKey(documentID: UUID(), utteranceIndex: 3, voiceID: "af_heart", engineID: "kokoro", normalizerVersion: 1, segmenterVersion: 1) != base)
    }

    @Test func roundTripsThroughRawValue() {
        #expect(RenderKey(rawValue: key().rawValue) == key())
    }
}
