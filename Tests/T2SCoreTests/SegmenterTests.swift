import Testing
@testable import T2SCore

@Suite struct SegmenterTests {
    let seg = Segmenter(normalizer: TextNormalizer())
    func block(_ text: String, offset: Int = 100) -> SourceBlock {
        SourceBlock(text: text, position: Position(resourceHref: "ch1.xhtml", progression: 0.25, charOffset: offset))
    }

    @Test func splitsSentencesWithOffsets() {
        let us = seg.segment(block("Hello world. This is a test."))
        #expect(us.map(\.source) == ["Hello world.", "This is a test."])
        #expect(us.map(\.position.charOffset) == [100, 113])
        #expect(us.allSatisfy { $0.position.resourceHref == "ch1.xhtml" && $0.position.progression == 0.25 })
    }

    @Test func normalizesSpokenAndKeepsSource() {
        let u = seg.segment(block("Dr. Smith paid $5."))[0]
        #expect(u.source == "Dr. Smith paid $5.")
        #expect(u.spoken == "Doctor Smith paid five dollars.")
        #expect(u.spans.isEmpty == false)
        #expect(u.duration.isActual == false)
        #expect(u.duration.seconds > 0)
    }

    @Test func offsetsUseUTF16() {
        let us = seg.segment(block("Café 😀 ok. Next."))
        #expect(us[1].position.charOffset == 100 + "Café 😀 ok. ".utf16.count)
    }

    @Test func splitsOverlongSentencesAtClauses() {
        let long = Array(repeating: "clause one, clause two; clause three", count: 6).joined(separator: ", ") + "."
        let us = Segmenter(normalizer: TextNormalizer(), maxUtteranceLength: 80).segment(block(long))
        #expect(us.count >= 3)
        #expect(us.allSatisfy { $0.source.utf16.count <= 80 })
        #expect(us.map(\.source).joined(separator: " ") == long)   // nothing lost, nothing duplicated
        #expect(us[1].position.charOffset! > us[0].position.charOffset!)
    }

    @Test func dropsEmptyAndWhitespaceOnly() {
        #expect(seg.segment(block("   \n  ")).isEmpty)
    }

    @Test func estimatorIsProportionalWithFloor() {
        #expect(DurationEstimator.estimate(spoken: "") == 0.5)
        #expect(DurationEstimator.estimate(spoken: String(repeating: "a", count: 150)) == 10)
    }
}
