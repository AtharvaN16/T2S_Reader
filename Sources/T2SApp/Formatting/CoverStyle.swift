import Foundation

/// What a generated cover is made from when a document has no art of its own: which of the
/// palette's colours a title gets, the letter that stands for it at thumbnail size, and the
/// masthead a web page or pasted text carries — its site, or the day it was written.
public enum CoverStyle {
    /// A stable slot in a palette of `count` colours for a title: the same book gets the same
    /// colour on every launch and every device (Swift's own `hashValue` is seeded per process),
    /// and two titles that differ only in case or padding get the same one. FNV-1a over UTF-8.
    public static func paletteIndex(for title: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let key = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return Int(hash % UInt32(count))
    }

    /// The first letter or digit of a title, uppercased — the mark on a cover too small for words.
    /// A bullet when there is none.
    public static func monogram(for title: String) -> String {
        guard let first = title.unicodeScalars.first(where: { CharacterSet.alphanumerics.contains($0) }) else { return "•" }
        return String(Character(first)).uppercased()
    }

    /// A page's site, as a person would say it: the host without a leading "www.", lowercased.
    /// The whole string when the URL has no host at all.
    public static func host(of url: URL) -> String {
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The day a text was written, short: "9 Sept" / "Sep 9" by locale.
    public static func dateLabel(for date: Date, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).day().month(.abbreviated))
    }
}
