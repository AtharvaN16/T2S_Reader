import Foundation
import T2SLibrary

/// "Paste text" (spec §2.4.5 rev 7): plain text becomes an article with no source URL. Blank lines
/// separate paragraphs; everything is escaped, so the body is always well-formed.
public enum PlainTextArticle {
    public static func content(title: String, body: String) -> ArticleContent {
        let paragraphs = body.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let xhtml = paragraphs.map { "<p>\(escape($0))</p>" }.joined()
        let trimmedTitle = stripControls(title).trimmingCharacters(in: .whitespacesAndNewlines)
        return ArticleContent(title: trimmedTitle.isEmpty ? defaultTitle(for: body) : trimmedTitle, bodyXHTML: xhtml)
    }

    /// The first non-blank line, cut to 80 characters; "Pasted text" when there is none.
    public static func defaultTitle(for body: String) -> String {
        guard let line = body.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else { return "Pasted text" }
        return line.count > 80 ? String(line.prefix(80)) + "…" : line
    }

    /// Drops the C0 controls (and DEL) that XML 1.0 forbids before escaping. Text pasted out of a
    /// PDF commonly carries `\u{0C}`; leaving it in makes `ArticleEPUBWriter` throw and the user
    /// sees "The article text couldn't be converted." for text that looked perfectly ordinary.
    static func stripControls(_ s: String) -> String {
        String(s.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x09, 0x0A, 0x0D: return true                       // tab, newline, carriage return
            case 0x00...0x1F, 0x7F: return false
            default: return true
            }
        })
    }

    static func escape(_ s: String) -> String {
        let cleaned = stripControls(s)
        return cleaned.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
