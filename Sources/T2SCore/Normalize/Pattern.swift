import Foundation

/// NSRegularExpression is immutable and thread-safe; it just is not annotated Sendable.
struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }
}

extension NSTextCheckingResult {
    func group(_ i: Int, in s: String) -> String? {
        let r = range(at: i)
        guard r.location != NSNotFound else { return nil }
        return (s as NSString).substring(with: r)
    }
}

extension NormalizedText {
    /// Applies `body` to every match, right to left, so earlier offsets stay valid.
    /// `body` receives the match and the spoken text the matches were computed on;
    /// return nil to leave a match untouched.
    mutating func replaceMatches(of pattern: Pattern, with body: (NSTextCheckingResult, String) -> String?) {
        let original = spoken
        let matches = pattern.regex.matches(in: original, range: NSRange(location: 0, length: (original as NSString).length))
        for m in matches.reversed() {
            guard let replacement = body(m, original) else { continue }
            let r = m.range.location..<(m.range.location + m.range.length)
            replace(spokenRange: r, with: replacement)
        }
    }

    mutating func replaceMatches(of pattern: Pattern, template: String) {
        replaceMatches(of: pattern) { m, s in
            pattern.regex.replacementString(for: m, in: s, offset: 0, template: template)
        }
    }
}
