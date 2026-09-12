import Foundation
import Testing
@testable import T2SCore

@Suite struct ClauseSplitterTests {
    @Test func textWithinTheLimitIsOnePiece() {
        #expect(ClauseSplitter.pieces(of: "Short enough.", maxLength: 80) == ["Short enough."])
    }

    @Test func cutsAtTheLastClauseBoundaryBeforeTheLimit() {
        let text = "one two three, four five six; seven eight nine, ten"
        let pieces = ClauseSplitter.pieces(of: text, maxLength: 20)
        #expect(pieces == ["one two three,", "four five six;", "seven eight nine,", "ten"])
        #expect(pieces.allSatisfy { ($0 as NSString).length <= 20 })
    }

    @Test func fallsBackToWhitespaceThenAHardCut() {
        #expect(ClauseSplitter.pieces(of: "alpha beta gamma delta", maxLength: 11) == ["alpha beta", "gamma", "delta"])
        #expect(ClauseSplitter.pieces(of: "abcdefghij", maxLength: 4) == ["abcd", "efgh", "ij"])
    }

    @Test func aHardCutNeverSplitsASurrogatePair() {
        let text = "ab😀cd"                                          // 😀 is two UTF-16 units
        let pieces = ClauseSplitter.pieces(of: text, maxLength: 3)
        #expect(pieces == ["ab", "😀c", "d"])                        // the pair moved whole into the next piece
        #expect(pieces[1].unicodeScalars.contains("😀"))
    }

    @Test func cutsCoverTheTextExactlyAndInOrder() {
        let text = "First clause here, second clause there; third clause, and a fourth one."
        let cuts = ClauseSplitter.cuts(in: text, maxLength: 25)
        let ns = text as NSString
        #expect(cuts.first?.location == 0)
        #expect(cuts.last.map { $0.location + $0.length } == ns.length)
        for (a, b) in zip(cuts, cuts.dropFirst()) { #expect(a.location + a.length == b.location) }
        #expect(cuts.allSatisfy { $0.length <= 25 })
    }

    @Test func whitespaceOnlyPiecesAreDropped() {
        // "one," then a window of four spaces, cut at its last space: that piece trims to nothing.
        #expect(ClauseSplitter.pieces(of: "one,    two", maxLength: 4) == ["one,", "two"])
    }
}
