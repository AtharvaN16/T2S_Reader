import Foundation
import ReadiumShared
import Testing
import T2SCore
@testable import T2SReadium

@Suite struct LocatorMappingTests {
    @Test func positionRoundTripsThroughALocator() throws {
        let position = Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0.4, charOffset: 12,
                                cssSelector: "html > body > p:nth-child(2)")
        let locator = try #require(LocatorMapping.locator(for: position))
        #expect(locator.href.string == "OEBPS/ch1.xhtml")
        #expect(locator.mediaType == .xhtml)
        #expect(locator.locations.progression == 0.4)
        #expect(locator.locations.otherLocations["cssSelector"] == .string("html > body > p:nth-child(2)"))
        var back = LocatorMapping.position(for: locator)
        #expect(back.charOffset == nil)                                     // a Locator carries no char offset
        back.charOffset = 12
        #expect(back == position)
    }

    @Test func wordHighlightCarriesQuoteAndContext() {
        let source = "The quick brown fox jumps over the lazy dog."
        let n = source.utf16.count
        let utterance = Utterance(position: Position(resourceHref: "OEBPS/ch1.xhtml", progression: 0, charOffset: 0,
                                                     cssSelector: "p:nth-child(1)"),
                                  source: source, spoken: source,
                                  spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], duration: .estimated(3))
        let timeline = Timeline(chapters: [Chapter(title: "1", position: utterance.position, utterances: [utterance])])
        let range = HighlightRange(utteranceIndex: 0, position: utterance.position, sourceRange: 10..<15)
        let locator = LocatorMapping.locator(for: range, in: timeline)
        #expect(locator?.text.highlight == "brown")
        #expect(locator?.text.before == "The quick ")
        #expect(locator?.text.after == " fox jumps over the lazy dog.")
        #expect(locator?.locations.otherLocations["cssSelector"] == .string("p:nth-child(1)"))
        #expect(LocatorMapping.locator(for: HighlightRange(utteranceIndex: 3, position: utterance.position, sourceRange: 0..<1), in: timeline) == nil)
    }

    @Test func contextIsCappedAtContextLength() {
        let source = String(repeating: "a", count: 200) + "WORD" + String(repeating: "b", count: 200)
        let n = source.utf16.count
        let utterance = Utterance(position: Position(resourceHref: "OEBPS/x.xhtml", progression: 0), source: source, spoken: source,
                                  spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], duration: .estimated(3))
        let timeline = Timeline(chapters: [Chapter(title: "1", position: utterance.position, utterances: [utterance])])
        let locator = LocatorMapping.locator(for: HighlightRange(utteranceIndex: 0, position: utterance.position, sourceRange: 200..<204), in: timeline)
        #expect(locator?.text.highlight == "WORD")
        #expect(locator?.text.before?.count == LocatorMapping.contextLength)
        #expect(locator?.text.after?.count == LocatorMapping.contextLength)
    }
}
