import Testing
@testable import T2SCore

@Suite struct RepeatedLineFilterTests {
    let words = ["alpha", "beta", "gamma", "delta", "epsilon"]
    func page(_ n: Int, body: [String]) -> [String] {
        ["THE GREAT BOOK — Chapter 2"] + body + ["Page \(n)"]
    }

    @Test func dropsHeadersFootersAndPageNumbers() {
        let pages = (1...5).map { n in page(n, body: ["The \(words[n - 1]) paragraph.", "It continues about \(words[n - 1])."]) }
        let out = RepeatedLineFilter.filter(pages: pages)
        #expect(out.count == 5)
        #expect(out[0] == ["The alpha paragraph.", "It continues about alpha."])
        #expect(out[4] == ["The epsilon paragraph.", "It continues about epsilon."])
    }

    @Test func keepsHeaderBelowThreshold() {
        let pages = (1...2).map { n in page(n, body: ["Body \(words[n - 1])"]) }
        let out = RepeatedLineFilter.filter(pages: pages)
        #expect(out[0].first == "THE GREAT BOOK — Chapter 2")
        #expect(out[0].last == "Body alpha")            // bare page numbers always go
    }

    @Test func keepsRepeatedLinesAwayFromEdges() {
        // A refrain repeated mid-page on every page is body text, not a header.
        let pages = (1...4).map { n in ["Header", "Opening \(words[n - 1]).", "Middle \(words[n - 1]).", "Once upon a time.", "More \(words[n - 1]).", "Closing \(words[n - 1]).", "Footer"] }
        let out = RepeatedLineFilter.filter(pages: pages)
        #expect(out.allSatisfy { $0.contains("Once upon a time.") })
        #expect(out[0].first == "Opening alpha.")
        #expect(out[0].last == "Closing alpha.")
    }

    @Test func bareNumbersAndPageOfGo() {
        let out = RepeatedLineFilter.filter(pages: [["  12  ", "text", "Page 3 of 9", "page 4"]])
        #expect(out == [["text"]])
    }
}
