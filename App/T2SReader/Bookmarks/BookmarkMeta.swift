// App/T2SReader/Bookmarks/BookmarkMeta.swift
import SwiftUI
import T2SApp

/// Where a bookmark sits, in one line of small print: the moment on the clock it was taken at, then
/// the chapter it falls in. One view for both surfaces that print it — the row and the opened
/// bookmark — so the line reads the same in the list and on the screen you open from the list.
///
/// **One time, not a span** (owner, 2026-09-13: "just keep the first timestamp"). It read
/// `1:34:18 – 1:34:30`, which is the length of one spoken sentence — a fact nobody needs and twelve
/// characters of clock to read past. A bookmark is a place, and a place is a single time.
///
/// **The clock is orange** (owner, 2026-09-13), the app's accent: it is the one thing on the line
/// you actually scan for, and the mark a bookmark is *for*. The chapter stays grey behind it, in
/// the plain cut against the clock's heavier one (owner, 2026-09-12: "use different weights to make
/// them look different"), with the dot between them fainter than either.
struct BookmarkMeta: View {
    var entry: BookmarkEntry
    /// The opened bookmark's own line reads bigger and heavier than a row's (owner, 2026-09-12):
    /// it carries more of the screen there, with the row's small print left as-is.
    var emphasized: Bool = false
    /// Whether the chapter follows the clock. The opened bookmark says the chapter in its header
    /// now, under the book's name (owner, 2026-09-13), so down here it would be said twice; a row
    /// has no header of its own and still carries it.
    var showsChapter: Bool = true

    /// The separator's diameter at the default text size, growing with the line it punctuates.
    @ScaledMetric(relativeTo: .footnote) private var dotBase: CGFloat = 4

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.timeText).font(timeFont).foregroundStyle(Tokens.accent)
            if showsChapter, !entry.chapterTitle.isEmpty {
                // A drawn dot rather than a typed `·` (owner, 2026-09-13: bigger, and a lighter
                // grey). The middle dot is a hair of ink at 13pt and grows only by growing the
                // type around it, which would take the line's height with it; a circle takes the
                // size it is given and leaves the row alone. `ink3` was nearly the page itself in
                // the dark — `ink2` is the chapter's own grey, so the separator reads as part of
                // the line rather than a smudge on it. It scales with the small print it sits in.
                Circle().fill(Tokens.ink2)
                    .frame(width: dotSize, height: dotSize)
                Text(entry.chapterTitle).font(chapterFont).foregroundStyle(Tokens.ink2)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.label(for: entry))
    }

    private var timeFont: Font { emphasized ? .custom("Inter-Bold", size: 17) : TypeRole.metaStrong.font }
    private var chapterFont: Font { emphasized ? .custom("Inter-SemiBold", size: 17) : TypeRole.meta.font }
    private var dotSize: CGFloat { emphasized ? dotBase * 1.25 : dotBase }

    /// The same two facts as one phrase, for a surface that reads the whole bookmark as one element.
    static func label(for entry: BookmarkEntry) -> String {
        entry.chapterTitle.isEmpty ? entry.timeText : "\(entry.timeText), \(entry.chapterTitle)"
    }
}
