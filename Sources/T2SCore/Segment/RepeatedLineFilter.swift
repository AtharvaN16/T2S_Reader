import Foundation

/// Spec §4.1 rule 2: lines recurring at the top or bottom of many pages are running
/// headers or footers; bare page numbers are always dropped.
public enum RepeatedLineFilter {
    static let pageNumber = Pattern("^\\s*(?:page\\s+)?\\d+(?:\\s+of\\s+\\d+)?\\s*$", .caseInsensitive)
    static let digits = Pattern("\\d+")

    public static func filter(pages: [[String]], minPages: Int = 3, edge: Int = 2) -> [[String]] {
        var pagesSeen: [String: Set<Int>] = [:]
        for (p, lines) in pages.enumerated() {
            let e = min(edge, max(1, lines.count / 4))
            let edgeLines = Array(lines.prefix(e)) + Array(lines.suffix(e))
            for line in edgeLines {
                pagesSeen[mask(line), default: []].insert(p)
            }
        }
        let recurring = Set(pagesSeen.filter { $0.value.count >= minPages }.keys)

        return pages.map { lines in
            let e = min(edge, max(1, lines.count / 4))
            return lines.enumerated().compactMap { i, line in
                if isPageNumber(line) { return nil }
                let atEdge = i < e || i >= lines.count - e
                if atEdge && recurring.contains(mask(line)) { return nil }
                return line
            }
        }
    }

    private static func mask(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let ns = trimmed as NSString
        return digits.regex.stringByReplacingMatches(in: trimmed, range: NSRange(location: 0, length: ns.length), withTemplate: "#")
    }

    private static func isPageNumber(_ line: String) -> Bool {
        let ns = line as NSString
        return pageNumber.regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
    }
}
