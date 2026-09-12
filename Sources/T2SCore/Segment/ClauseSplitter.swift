import Foundation

/// The one rule for cutting text that is too long for a single call: at the last clause boundary
/// before the limit, else the last whitespace, else a hard cut that never divides a surrogate
/// pair. The segmenter applies it to an overlong sentence; the cloud engine applies it to an
/// utterance longer than a hosted request may carry. Lengths are UTF-16 units.
public enum ClauseSplitter {
    public static let clauseBoundaries = CharacterSet(charactersIn: ";:,—–")

    /// Ranges into `text`, in order, covering it exactly. Untrimmed: a piece after a whitespace cut
    /// starts with that whitespace. `maxLength` must be at least 2 so a hard cut can always make
    /// progress past a surrogate pair.
    public static func cuts(in text: String, maxLength: Int) -> [NSRange] {
        precondition(maxLength >= 2, "maxLength must be at least 2")
        let ns = text as NSString
        guard ns.length > maxLength else { return [NSRange(location: 0, length: ns.length)] }
        var ranges: [NSRange] = []
        var start = 0
        while ns.length - start > maxLength {
            let window = NSRange(location: start, length: maxLength)
            var cut = ns.rangeOfCharacter(from: clauseBoundaries, options: .backwards, range: window).location
            if cut != NSNotFound && cut > start { cut += 1 }         // the mark stays with its clause
            if cut == NSNotFound || cut <= start {
                cut = ns.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards, range: window).location
            }
            if cut == NSNotFound || cut <= start {
                cut = start + maxLength
                if cut - 1 > start && CFStringIsSurrogateHighCharacter(ns.character(at: cut - 1)) { cut -= 1 }
            }
            ranges.append(NSRange(location: start, length: cut - start))
            start = cut
        }
        ranges.append(NSRange(location: start, length: ns.length - start))
        return ranges
    }

    /// The pieces' text, each trimmed of surrounding whitespace; a piece that was only whitespace
    /// is dropped.
    public static func pieces(of text: String, maxLength: Int) -> [String] {
        let ns = text as NSString
        return cuts(in: text, maxLength: maxLength).compactMap { range in
            let piece = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            return piece.isEmpty ? nil : piece
        }
    }
}
