enum NumberWords {
    private static let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                               "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
                               "seventeen", "eighteen", "nineteen"]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    private static let scales: [(Int, String)] = [
        (1_000_000_000_000, "trillion"), (1_000_000_000, "billion"), (1_000_000, "million"), (1_000, "thousand"),
    ]

    /// Joins the tens and ones of a compound number with a space, not a hyphen
    /// ("twenty three", not "twenty-three"). Finding 2026-09-03-g2p-coverage.md,
    /// Decision → mitigation 1: MisakiSwift keeps the hyphen as a `—` token, which
    /// Kokoro may render as a pause.
    static func cardinal(_ n: Int) -> String {
        if n < 0 { return "minus " + cardinal(-n) }
        if n < 20 { return ones[n] }
        if n < 100 {
            let t = tens[n / 10]
            let o = n % 10
            return o == 0 ? t : "\(t) \(ones[o])"
        }
        if n < 1000 {
            let h = "\(ones[n / 100]) hundred"
            let r = n % 100
            return r == 0 ? h : "\(h) \(cardinal(r))"
        }
        for (value, name) in scales where n >= value {
            let head = "\(cardinal(n / value)) \(name)"
            let r = n % value
            return r == 0 ? head : "\(head) \(cardinal(r))"
        }
        return String(n)
    }

    static func ordinal(_ n: Int) -> String {
        let c = cardinal(n)
        let irregular = ["one": "first", "two": "second", "three": "third", "five": "fifth",
                         "eight": "eighth", "nine": "ninth", "twelve": "twelfth"]
        let lastStart = c.lastIndex(where: { $0 == " " || $0 == "-" }).map { c.index(after: $0) } ?? c.startIndex
        let last = String(c[lastStart...])
        let replacement: String
        if let irr = irregular[last] {
            replacement = irr
        } else if last.hasSuffix("y") {
            replacement = String(last.dropLast()) + "ieth"
        } else {
            replacement = last + "th"
        }
        return String(c[..<lastStart]) + replacement
    }

    static func year(_ y: Int) -> String {
        guard (1000...2999).contains(y) else { return cardinal(y) }
        let hi = y / 100
        let lo = y % 100
        if y % 1000 == 0 { return cardinal(y) }
        if y >= 2000 && y < 2010 { return "two thousand \(cardinal(lo))" }
        if lo == 0 { return "\(cardinal(hi)) hundred" }
        if lo < 10 { return "\(cardinal(hi)) oh \(cardinal(lo))" }
        return "\(cardinal(hi)) \(cardinal(lo))"
    }

    static func digits(_ s: String) -> String {
        s.compactMap { $0.wholeNumberValue }.map { ones[$0] }.joined(separator: " ")
    }
}
