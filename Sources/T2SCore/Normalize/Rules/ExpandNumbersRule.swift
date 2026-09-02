import Foundation

/// Rule 4b (spec §4.1): ordinals, numerals, units, currency. Dotted version strings are left alone.
public struct ExpandNumbersRule: NormalizerRule {
    static let units = Pattern("\\b(\\d+(?:\\.\\d+)?)\\s?(km|kg|cm|mm|mph|GB|MB|ms|min)\\b")
    static let currency = Pattern("([$£€])(\\d{1,3}(?:,\\d{3})+|\\d+)(?:\\.(\\d{1,2}))?\\b")
    static let percent = Pattern("\\b(\\d+(?:\\.\\d+)?)%")
    static let ordinal = Pattern("\\b(\\d+)(?:st|nd|rd|th)\\b", .caseInsensitive)
    // Lookarounds: never inside a longer number or a dotted version string, but a
    // sentence-ending period after the number is fine.
    static let decimal = Pattern("(?<![\\d.])(\\d+)\\.(\\d+)(?!\\d)(?!\\.\\d)")
    static let decade = Pattern("(?<![\\d.,])(1\\d{3}|2\\d{3}|[1-9]0)'?s(?![\\p{L}\\d])")
    static let year = Pattern("(?<![\\d.,])(1\\d{3}|2\\d{3})(?!\\d)(?![.,]\\d)")
    static let cardinal = Pattern("(?<![\\d.])(\\d{1,3}(?:,\\d{3})+|\\d+)(?!\\d)(?![.,]\\d)")

    static let unitNames: [String: (String, String)] = [
        "km": ("kilometer", "kilometers"), "kg": ("kilogram", "kilograms"), "cm": ("centimeter", "centimeters"),
        "mm": ("millimeter", "millimeters"), "mph": ("miles per hour", "miles per hour"),
        "GB": ("gigabyte", "gigabytes"), "MB": ("megabyte", "megabytes"), "ms": ("millisecond", "milliseconds"),
        "min": ("minute", "minutes"),
    ]
    static let currencyNames: [String: (String, String, String, String)] = [
        "$": ("dollar", "dollars", "cent", "cents"),
        "£": ("pound", "pounds", "penny", "pence"),
        "€": ("euro", "euros", "cent", "cents"),
    ]

    public init() {}

    public func apply(_ input: NormalizedText) -> NormalizedText {
        var t = input
        t.replaceMatches(of: Self.units) { m, s in
            guard let num = m.group(1, in: s), let unit = m.group(2, in: s), let names = Self.unitNames[unit] else { return nil }
            return "\(num) \(num == "1" ? names.0 : names.1)"
        }
        t.replaceMatches(of: Self.currency) { m, s in
            guard let sym = m.group(1, in: s), let names = Self.currencyNames[sym],
                  let whole = Int(m.group(2, in: s)!.replacingOccurrences(of: ",", with: "")) else { return nil }
            let cents = m.group(3, in: s).flatMap { Int($0.count == 1 ? $0 + "0" : $0) } ?? 0
            let major = "\(NumberWords.cardinal(whole)) \(whole == 1 ? names.0 : names.1)"
            let minor = "\(NumberWords.cardinal(cents)) \(cents == 1 ? names.2 : names.3)"
            if cents == 0 { return major }
            if whole == 0 { return minor }
            return "\(major) and \(minor)"
        }
        t.replaceMatches(of: Self.percent) { m, s in
            guard let num = m.group(1, in: s) else { return nil }
            return "\(Self.spokenNumber(num)) percent"
        }
        t.replaceMatches(of: Self.ordinal) { m, s in
            m.group(1, in: s).flatMap(Int.init).map(NumberWords.ordinal)
        }
        t.replaceMatches(of: Self.decimal) { m, s in
            guard let whole = m.group(1, in: s).flatMap(Int.init), let frac = m.group(2, in: s) else { return nil }
            return "\(NumberWords.cardinal(whole)) point \(NumberWords.digits(frac))"
        }
        t.replaceMatches(of: Self.decade) { m, s in
            guard let n = m.group(1, in: s).flatMap(Int.init) else { return nil }
            let words = n >= 1000 ? NumberWords.year(n) : NumberWords.cardinal(n)
            return words.hasSuffix("y") ? String(words.dropLast()) + "ies" : words + "s"
        }
        t.replaceMatches(of: Self.year) { m, s in
            m.group(1, in: s).flatMap(Int.init).map(NumberWords.year)
        }
        t.replaceMatches(of: Self.cardinal) { m, s in
            m.group(1, in: s).flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }.map(NumberWords.cardinal)
        }
        return t
    }

    private static func spokenNumber(_ s: String) -> String {
        if let dot = s.firstIndex(of: "."), let whole = Int(s[..<dot]) {
            return "\(NumberWords.cardinal(whole)) point \(NumberWords.digits(String(s[s.index(after: dot)...])))"
        }
        return Int(s).map(NumberWords.cardinal) ?? s
    }
}
