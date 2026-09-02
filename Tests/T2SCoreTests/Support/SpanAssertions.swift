import Foundation
import Testing
@testable import T2SCore

/// Spec §8: every spoken word range projects back to a non-empty source range.
func expectEveryWordMapsToSource(_ t: NormalizedText, allowInsertions: Bool = false,
                                 sourceLocation: SourceLocation = #_sourceLocation) {
    let regex = try! NSRegularExpression(pattern: "\\S+")
    let ns = t.spoken as NSString
    for m in regex.matches(in: t.spoken, range: NSRange(location: 0, length: ns.length)) {
        let r = m.range.location..<(m.range.location + m.range.length)
        let src = t.sourceRange(forSpoken: r)
        if src.isEmpty && !allowInsertions {
            Issue.record("word \"\(ns.substring(with: m.range))\" at \(r) maps to empty source range", sourceLocation: sourceLocation)
        }
    }
}
