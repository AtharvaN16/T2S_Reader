// App/T2SReader/Bookmarks/BookmarkMeta.swift
import SwiftUI
import T2SApp

/// Where a bookmark sits, in one line of small print: the span of the clock it covers, then the
/// chapter it falls in. One view for both surfaces that print it — the row and the opened bookmark
/// — so the line reads the same in the list and on the screen you open from the list.
///
/// The two halves are in two weights (owner, 2026-09-12: "use different weights to make them look
/// different"). The clock is the half you scan for, so it carries the heavier cut; the chapter
/// follows in the plain one, with the dot between them fainter than either. Same size and the same
/// grey for both: a line of small print stays a line of small print.
struct BookmarkMeta: View {
    var entry: BookmarkEntry
    /// The opened bookmark's own line reads bigger and heavier than a row's (owner, 2026-09-12):
    /// it carries more of the screen there, with the row's small print left as-is.
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.rangeText).font(timeFont).foregroundStyle(Tokens.ink2)
            if !entry.chapterTitle.isEmpty {
                Text("·").font(dotFont).foregroundStyle(Tokens.ink3)
                Text(entry.chapterTitle).font(chapterFont).foregroundStyle(Tokens.ink2)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.label(for: entry))
    }

    private var timeFont: Font { emphasized ? .custom("Inter-Bold", size: 17) : TypeRole.metaStrong.font }
    private var chapterFont: Font { emphasized ? .custom("Inter-SemiBold", size: 17) : TypeRole.meta.font }
    private var dotFont: Font { emphasized ? .custom("Inter-Regular", size: 17) : TypeRole.meta.font }

    /// The same two facts as one phrase, for a surface that reads the whole bookmark as one element.
    static func label(for entry: BookmarkEntry) -> String {
        entry.chapterTitle.isEmpty ? entry.rangeText : "\(entry.rangeText), \(entry.chapterTitle)"
    }
}
