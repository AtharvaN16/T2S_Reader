import T2SApp
import UIKit

/// `ReaderText` → one attributed string (spec 2026-09-07 §4): the type roles of spec §2.4.1 by
/// PostScript name, paragraph styles for spacing and line height, and the two dynamic colours the
/// text uses — `ink` everywhere, `ink2` on the byline. Both are dynamic `UIColor`s resolved at draw
/// time, so a theme change recolours without a rebuild. (They are attributes rather than the view's
/// `textColor` because that property applies to the whole string and would flatten the byline.)
/// Nonisolated and pure so the page can build it off the main actor, and cancellable a paragraph at
/// a time: a slider drag emits a dozen scales, and each superseded typeset must stop rather than
/// finish a whole book beside the TTS inference.
enum ReaderTypesetter {
    static let bodySize: CGFloat = 18

    private static func font(_ name: String, _ size: CGFloat, fallback: UIFont.Weight) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: fallback)
    }

    /// nil when the task building it was cancelled: the caller's string is superseded.
    static func attributedString(for text: ReaderText, scale: Double, lineHeight: Double,
                                 inkColor: UIColor, bylineColor: UIColor) -> NSAttributedString? {
        let body = bodySize * scale
        let result = NSMutableAttributedString()
        for (i, paragraph) in text.paragraphs.enumerated() {
            if Task.isCancelled { return nil }
            let font: UIFont
            var tracking: CGFloat = 0
            var before: CGFloat = 0
            var after: CGFloat = 0
            var color = inkColor
            var multiple = 1.15
            switch paragraph.kind {
            case .documentTitle:
                font = Self.font("InterDisplay-Black", 34, fallback: .black)
                tracking = -0.03 * 34
                after = 8
            case .byline:
                font = Self.font("Inter-Regular", 13, fallback: .regular)
                color = bylineColor
                after = 24
            case .chapterTitle:
                font = Self.font("InterDisplay-ExtraBold", 26, fallback: .heavy)
                tracking = -0.025 * 26
                before = 40
                after = 16
            case .heading(let level):
                font = Self.font("Inter-SemiBold", body * (level <= 3 ? 1.15 : 1.0), fallback: .semibold)
                before = 24
                after = 8
            case .body:
                font = Self.font("Inter-Regular", body, fallback: .regular)
                after = 0.75 * body
                multiple = lineHeight
            }
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = multiple
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = after
            style.hyphenationFactor = 0
            style.alignment = .natural
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style,
                                                             .foregroundColor: color]
            if tracking != 0 { attributes[.kern] = tracking }
            result.append(NSAttributedString(string: paragraph.text, attributes: attributes))
            if i < text.paragraphs.count - 1 {
                // The separator carries its paragraph's style: TextKit reads it from the terminator too.
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        assert(result.length == text.length, "typeset length \(result.length) ≠ model length \(text.length)")
        return result
    }
}
