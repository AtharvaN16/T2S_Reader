import Testing
@testable import T2SCore

@Suite struct NumberWordsTests {
    @Test(arguments: [
        (0, "zero"), (7, "seven"), (13, "thirteen"), (20, "twenty"), (21, "twenty one"),
        (100, "one hundred"), (101, "one hundred one"), (999, "nine hundred ninety nine"),
        (1000, "one thousand"), (1234, "one thousand two hundred thirty four"),
        (1_000_000, "one million"), (2_500_017, "two million five hundred thousand seventeen"),
        (-5, "minus five"),
    ])
    func cardinal(n: Int, words: String) { #expect(NumberWords.cardinal(n) == words) }

    @Test(arguments: [
        (1, "first"), (2, "second"), (3, "third"), (4, "fourth"), (5, "fifth"), (8, "eighth"),
        (9, "ninth"), (12, "twelfth"), (20, "twentieth"), (21, "twenty first"), (100, "one hundredth"),
        (1000, "one thousandth"),
    ])
    func ordinal(n: Int, words: String) { #expect(NumberWords.ordinal(n) == words) }

    @Test(arguments: [
        (1999, "nineteen ninety nine"), (1900, "nineteen hundred"), (1905, "nineteen oh five"),
        (2000, "two thousand"), (2005, "two thousand five"), (2010, "twenty ten"),
        (2024, "twenty twenty four"), (1066, "ten sixty six"), (3000, "three thousand"),
    ])
    func year(n: Int, words: String) { #expect(NumberWords.year(n) == words) }

    @Test func digitsSpokenIndividually() {
        #expect(NumberWords.digits("305") == "three zero five")
    }

    // Finding 2026-09-03-g2p-coverage.md, Decision → mitigation 1: MisakiSwift keeps a `—`
    // token for the hyphen inside "twenty-three", which Kokoro may render as a pause, so
    // compound numbers join with a space instead.
    @Test func compoundNumbersUseSpacesForMisakiG2P() {
        #expect(NumberWords.cardinal(23) == "twenty three")
        #expect(NumberWords.ordinal(42) == "forty second")
        #expect(NumberWords.year(1905) == "nineteen oh five")
    }
}
