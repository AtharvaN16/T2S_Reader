import Testing
@testable import T2SCore

@Suite struct SegmenterTests {
    /// The per-sentence segmenter every test below was written against: `packLength: 0` keeps one
    /// sentence per utterance. The packing tests at the end construct their own.
    let seg = Segmenter(normalizer: TextNormalizer(), packLength: 0)
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
        let us = Segmenter(normalizer: TextNormalizer(), maxUtteranceLength: 80, packLength: 0).segment(block(long))
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

    @Test func piecesLocateThemselvesInTheBlock() {
        let text = "First clause here,\nsecond clause there; third clause, and a fourth one, then a fifth clause; the end."
        let us = Segmenter(normalizer: TextNormalizer(), maxUtteranceLength: 40, packLength: 0).segment(block(text, offset: 0))
        #expect(us.count >= 3)
        let units = Array(text.utf16)
        for u in us {
            let start = u.position.charOffset!
            let located = String(decoding: units[start..<(start + u.source.utf16.count)], as: UTF16.self)
            #expect(located == u.source, "piece at \(start)")
            #expect(u.source.first.map { !$0.isWhitespace } == true)
        }
    }

    // MARK: Packing (Plan 9: one Kokoro call per sentence left 800 ms of dead air after each)

    @Test func packsTwoShortSentencesIntoOneUtterance() {
        let us = Segmenter(normalizer: TextNormalizer(), packLength: 160).segment(block("Hello world. This is a test."))
        #expect(us.count == 1)
        #expect(us[0].source == "Hello world. This is a test.")
        #expect(us[0].position.charOffset == 100)
        #expect(us[0].spoken == "Hello world. This is a test.")
    }

    @Test func aSentenceThatWouldOverflowStartsTheNextUtterance() {
        let a = "First sentence is short."                     // 24
        let b = "Second sentence is also fairly short."         // 37 → 24 + 1 + 37 = 62
        let c = "Third sentence pushes the pack past the limit set for this test."   // would exceed 80
        let us = Segmenter(normalizer: TextNormalizer(), packLength: 80).segment(block([a, b, c].joined(separator: " "), offset: 0))
        #expect(us.map(\.source) == ["\(a) \(b)", c])
        #expect(us.map(\.position.charOffset) == [0, a.utf16.count + 1 + b.utf16.count + 1])
    }

    /// Neighbours here are all at least ``Segmenter/minUtteranceLength`` long, so the only rule under
    /// test is the budget: a sentence over it is its own utterance. (A five-character "Tiny." would
    /// now join its neighbour instead, which `aPieceTooShortToStandAloneGoesWithTheNext` covers.)
    @Test func aSentenceLongerThanThePackLengthStaysAlone() {
        let first = "A short enough opening line."
        let long = "This one sentence is on its own longer than the pack length used here."
        let last = "And a closing line here."
        let us = Segmenter(normalizer: TextNormalizer(), packLength: 40).segment(block("\(first) \(long) \(last)"))
        #expect(us.map(\.source) == [first, long, last])
    }

    @Test func packingNeverCrossesABlock() {
        let s = Segmenter(normalizer: TextNormalizer(), packLength: 160)
        let first = s.segment(block("One.", offset: 0))
        let second = s.segment(block("Two.", offset: 10))
        #expect(first.map(\.source) == ["One."])
        #expect(second.map(\.source) == ["Two."])
    }

    @Test func zeroPackLengthKeepsOneSentencePerUtterance() {
        let text = "Hello world. This is a test. And a third."
        let packed = Segmenter(normalizer: TextNormalizer(), packLength: 0).segment(block(text))
        #expect(packed.map(\.source) == ["Hello world.", "This is a test.", "And a third."])
    }

    @Test func packedPiecesLocateThemselvesInTheBlock() {
        let text = "First clause here,\nsecond clause there; third clause, and a fourth one, then a fifth clause; the end. Then more."
        let us = Segmenter(normalizer: TextNormalizer(), maxUtteranceLength: 40, packLength: 60).segment(block(text, offset: 0))
        #expect(us.count >= 2)
        let units = Array(text.utf16)
        for u in us {
            let start = u.position.charOffset!
            let located = String(decoding: units[start..<(start + u.source.utf16.count)], as: UTF16.self)
            #expect(located == u.source, "piece at \(start)")
            #expect(u.source.utf16.count <= 60)
        }
    }

    @Test func hardCutNeverSplitsASurrogatePair() {
        let text = String(repeating: "😀", count: 10)                       // 20 UTF-16 units, no spaces
        let us = Segmenter(normalizer: TextNormalizer(), maxUtteranceLength: 7, packLength: 0).segment(block(text, offset: 0))
        #expect(us.map(\.source).joined() == text)
        #expect(us.allSatisfy { $0.source.utf16.count % 2 == 0 })
    }

    /// A drop cap puts a line break inside the paragraph — "ELIZABETH'S\nEARLY YEARS were spent…" —
    /// and `NLTokenizer` ends a sentence at it, so the opening word became an utterance of eleven
    /// characters. Packing could not take it back: the sentence after it is 188 characters, so the
    /// pair is over `packLength`. A call that short is read far above the voice's narration pitch —
    /// `af_aoede` said it at 279 Hz against the paragraph's 176 Hz
    /// (`spikes/findings/2026-09-16-short-utterances.md`). It goes with the next piece whatever the
    /// packing budget says.
    @Test func aPieceTooShortToStandAloneGoesWithTheNext() {
        let block = SourceBlock(text: "ELIZABETH\u{2019}S\nEARLY YEARS were spent in Washington, D.C., where her father held a succession of jobs at government agencies ranging from the State Department to the Agency for International Development. Her mother worked as an aide on Capitol Hill.",
                                position: Position(resourceHref: "c", progression: 0, charOffset: 0))
        let utterances = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength).segment(block)
        #expect(utterances.count == 2)
        #expect(utterances[0].source.hasPrefix("ELIZABETH\u{2019}S\nEARLY YEARS were spent"))
        #expect(utterances[0].position.charOffset == 0)
        #expect(utterances[1].source.hasPrefix("Her mother worked"))
    }

    /// The same rule at the end of a block, where there is no next piece: the short tail joins the
    /// piece before it instead.
    @Test func aShortTailGoesWithThePieceBeforeIt() {
        let block = SourceBlock(text: "She had been thinking about the problem for most of the afternoon, and had got nowhere at all with it, nor had anyone else in the building that long day. Not yet.",
                                position: Position(resourceHref: "c", progression: 0, charOffset: 0))
        let utterances = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength).segment(block)
        #expect(utterances.count == 1)
        #expect(utterances[0].source.hasSuffix("Not yet."))
    }

    /// A block that is short all by itself stays as it is — there is nothing to join it to, and a
    /// one-line paragraph is the author's, not an artefact of the markup.
    @Test func aShortBlockIsLeftAlone() {
        let block = SourceBlock(text: "Not yet.", position: Position(resourceHref: "c", progression: 0, charOffset: 0))
        let utterances = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength).segment(block)
        #expect(utterances.count == 1)
        #expect(utterances[0].source == "Not yet.")
    }
}
